const asyncHandler = require('../utils/asyncHandler');
const AppError = require('../utils/AppError');
const Product = require('../models/Product');
const Order = require('../models/Order');
const Sale = require('../models/Sale');
const User = require('../models/User');
const DiscrepancyReport = require('../models/DiscrepancyReport');
const { getSalesReport, getCategoryBreakdown, getProductBreakdown } = require('../services/reportingService');
const Payment = require('../models/Payment');
const { PAYMENT_METHODS, PAYMENT_STATUSES } = require('../utils/constants');
const { currentOpenShift, getShiftReport } = require('../services/shiftService');
const { unreadCount } = require('../services/notificationService');
const { listAuditLogs } = require('../services/auditService');
const { ROLES, ORDER_STATUSES, DISCREPANCY_STATUSES } = require('../utils/constants');

// Spec §2: staff see daily figures for their own shift/sales only; admin and
// superadmin see consolidated daily/weekly/monthly/yearly reports.
const salesReport = asyncHandler(async (req, res) => {
  const query = { ...req.query };
  if (req.user.role === ROLES.STAFF) {
    if (query.period !== 'daily') throw new AppError(403, 'Staff may only view daily sales figures');
    query.source = 'pos';
    query.cashierId = req.user._id;
    if (!query.from && !query.to) {
      const start = new Date();
      start.setHours(0, 0, 0, 0);
      query.from = start;
    }
  }
  const report = await getSalesReport(query);
  res.json(report);
});

const categoryReport = asyncHandler(async (req, res) => {
  const categories = await getCategoryBreakdown(req.query);
  res.json({ categories });
});

const productReport = asyncHandler(async (req, res) => {
  const products = await getProductBreakdown(req.query);
  res.json({ products });
});

function startOfToday() {
  const d = new Date();
  d.setHours(0, 0, 0, 0);
  return d;
}

// One call that feeds each role's landing dashboard (spec §1: "each role
// lands on a different dashboard"). Only the sections the role may see are
// computed and returned.
const dashboard = asyncHandler(async (req, res) => {
  const { role } = req.user;
  const today = startOfToday();
  const out = { role, generatedAt: new Date().toISOString() };

  const openShift = await currentOpenShift(req.user._id);
  out.shift = openShift ? await getShiftReport(openShift) : null;
  out.unreadNotifications = await unreadCount(req.user);

  if (role === ROLES.STAFF) {
    const mine = await getSalesReport({ period: 'daily', source: 'pos', cashierId: req.user._id, from: today });
    const count = await Sale.countDocuments({ cashier: req.user._id, createdAt: { $gte: today } });
    out.mySalesToday = { ...mine.summary, salesCount: count };
    out.openDiscrepancies = await DiscrepancyReport.countDocuments({ reportedBy: req.user._id, status: DISCREPANCY_STATUSES.OPEN });
    return res.json(out);
  }

  const [todayAll, posCount, pendingOrders, lowStock, outOfStock, openDiscrepancies, categories] = await Promise.all([
    getSalesReport({ period: 'daily', source: 'all', from: today }),
    Sale.countDocuments({ createdAt: { $gte: today } }),
    Order.countDocuments({
      status: {
        $in: [
          ORDER_STATUSES.PENDING,
          ORDER_STATUSES.PAYMENT_SUBMITTED,
          ORDER_STATUSES.PAYMENT_UNDER_REVIEW,
          ORDER_STATUSES.PAYMENT_APPROVED,
          ORDER_STATUSES.CONFIRMED,
          ORDER_STATUSES.PROCESSING,
          ORDER_STATUSES.PACKING,
        ],
      },
    }),
    Product.countDocuments({ isActive: true, isMadeToOrder: false, currentStock: { $gt: 0 }, $expr: { $lte: ['$currentStock', '$reorderThreshold'] } }),
    Product.countDocuments({ isActive: true, isMadeToOrder: false, currentStock: { $lte: 0 } }),
    DiscrepancyReport.countDocuments({ status: DISCREPANCY_STATUSES.OPEN }),
    getCategoryBreakdown({ from: today }),
  ]);
  out.today = { ...todayAll.summary, posSalesCount: posCount };
  out.pendingOrders = pendingOrders;
  out.paymentsToReview = await Payment.countDocuments({ method: PAYMENT_METHODS.MANUAL_RECEIPT, status: PAYMENT_STATUSES.PENDING_REVIEW });
  out.lowStockCount = lowStock;
  out.outOfStockCount = outOfStock;
  out.openDiscrepancies = openDiscrepancies;
  out.categoriesToday = categories;

  if (role === ROLES.SUPERADMIN) {
    const [admins, staff, customers, audit] = await Promise.all([
      User.countDocuments({ role: ROLES.ADMIN, deletedAt: null, isActive: true }),
      User.countDocuments({ role: ROLES.STAFF, deletedAt: null, isActive: true }),
      User.countDocuments({ role: ROLES.CUSTOMER, deletedAt: null }),
      listAuditLogs({ limit: 8 }),
    ]);
    out.accounts = { admins, staff, customers };
    out.recentAudit = audit.logs;
  }

  res.json(out);
});

module.exports = { salesReport, categoryReport, productReport, dashboard };
