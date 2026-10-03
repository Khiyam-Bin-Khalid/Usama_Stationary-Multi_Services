const Sale = require('../models/Sale');
const AppError = require('../utils/AppError');
const asyncHandler = require('../utils/asyncHandler');
const { createSale } = require('../services/saleService');
const { ROLES } = require('../utils/constants');

const recordSale = asyncHandler(async (req, res) => {
  const { clientTxnId, items, paymentMethod, taxRate, branch, recordedOffline } = req.body;
  const { sale, alreadyExisted } = await createSale({
    clientTxnId,
    items,
    paymentMethod,
    taxRate,
    branch,
    recordedOffline,
    cashierId: req.user._id,
    cashierRole: req.user.role,
  });

  res.status(alreadyExisted ? 200 : 201).json({ sale, alreadyExisted });
});

const listSales = asyncHandler(async (req, res) => {
  const { from, to, category, shift, page, limit } = req.query;
  const filter = {};
  // Spec §3.3: staff see only their own transactions.
  if (req.user.role === ROLES.STAFF) filter.cashier = req.user._id;
  if (shift) filter.shift = shift;
  if (from || to) {
    filter.createdAt = {};
    if (from) filter.createdAt.$gte = new Date(from);
    if (to) filter.createdAt.$lte = new Date(to);
  }
  if (category) filter['items.category'] = category;

  const total = await Sale.countDocuments(filter);
  const sales = await Sale.find(filter)
    .sort({ createdAt: -1 })
    .skip((page - 1) * limit)
    .limit(limit)
    .populate('cashier', 'name email');

  res.json({ sales, total, page, limit });
});

const getSale = asyncHandler(async (req, res) => {
  const sale = await Sale.findById(req.params.id).populate('cashier', 'name email');
  if (!sale) throw new AppError(404, 'Sale not found');
  if (req.user.role === ROLES.STAFF && !sale.cashier._id.equals(req.user._id)) {
    throw new AppError(403, 'You may only view your own sales');
  }
  res.json({ sale });
});

module.exports = { recordSale, listSales, getSale };
