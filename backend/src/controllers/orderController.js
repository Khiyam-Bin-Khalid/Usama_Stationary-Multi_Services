const Order = require('../models/Order');
const Payment = require('../models/Payment');
const AppError = require('../utils/AppError');
const asyncHandler = require('../utils/asyncHandler');
const { createOrder, quoteOrder, updateOrderStatus } = require('../services/orderService');
const { createStripeCheckoutSession } = require('../services/paymentService');
const { logAction } = require('../services/auditService');
const { PAYMENT_METHODS, ORDER_STATUSES } = require('../utils/constants');

// Checkout summary (images, SKUs, quantities, unit prices, item totals,
// subtotal, discount, delivery, tax, grand total) before the customer confirms.
const quote = asyncHandler(async (req, res) => {
  res.json({ quote: await quoteOrder(req.body) });
});

const placeOrder = asyncHandler(async (req, res) => {
  const order = await createOrder({ customerId: req.user._id, ...req.body });

  let checkout = null;
  if (order.paymentMethod === PAYMENT_METHODS.STRIPE) {
    checkout = await createStripeCheckoutSession(order);
  }

  res.status(201).json({ order, checkout });
});

// Attaches the Payment document (receipt URL, review status/note) so both
// the customer and admin screens can show "receipt uploaded — under review".
async function withPayment(order) {
  const payment = await Payment.findOne({ order: order._id }).populate('reviewedBy', 'name role').lean();
  return { ...order.toObject(), payment };
}

const myOrders = asyncHandler(async (req, res) => {
  const orders = await Order.find({ customer: req.user._id }).sort({ createdAt: -1 });
  res.json({ orders });
});

const getMyOrder = asyncHandler(async (req, res) => {
  const order = await Order.findOne({ _id: req.params.id, customer: req.user._id });
  if (!order) throw new AppError(404, 'Order not found');
  res.json({ order: await withPayment(order) });
});

// Admin/staff: all orders, optionally filtered by one status or a group.
const listOrders = asyncHandler(async (req, res) => {
  const { status, statuses, paymentStatus, page, limit } = req.query;
  const filter = {};
  if (status) filter.status = status;
  if (statuses) {
    const list = statuses.split(',').map((s) => s.trim()).filter((s) => Object.values(ORDER_STATUSES).includes(s));
    if (list.length) filter.status = { $in: list };
  }
  if (paymentStatus) filter.paymentStatus = paymentStatus;

  const total = await Order.countDocuments(filter);
  const orders = await Order.find(filter)
    .sort({ createdAt: -1 })
    .skip((page - 1) * limit)
    .limit(limit)
    .populate('customer', 'name email phone');

  res.json({ orders, total, page, limit });
});

const getOrder = asyncHandler(async (req, res) => {
  const order = await Order.findById(req.params.id)
    .populate('customer', 'name email phone')
    .populate('statusHistory.by', 'name role');
  if (!order) throw new AppError(404, 'Order not found');
  res.json({ order: await withPayment(order) });
});

const changeOrderStatus = asyncHandler(async (req, res) => {
  const order = await updateOrderStatus({ orderId: req.params.id, ...req.body, actorId: req.user._id });
  await logAction({ actor: req.user._id, action: 'order.status_change', entityType: 'Order', entityId: order._id, details: req.body });
  res.json({ order });
});

// Counts per status for the admin order-management tabs.
const statusCounts = asyncHandler(async (req, res) => {
  const rows = await Order.aggregate([{ $group: { _id: '$status', count: { $sum: 1 } } }]);
  const counts = Object.fromEntries(Object.values(ORDER_STATUSES).map((s) => [s, 0]));
  for (const r of rows) counts[r._id] = r.count;
  res.json({ counts });
});

module.exports = { quote, placeOrder, myOrders, getMyOrder, listOrders, getOrder, changeOrderStatus, statusCounts };
