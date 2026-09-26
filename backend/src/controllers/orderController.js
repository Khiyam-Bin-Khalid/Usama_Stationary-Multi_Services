const Order = require('../models/Order');
const AppError = require('../utils/AppError');
const asyncHandler = require('../utils/asyncHandler');
const { createOrder, updateOrderStatus } = require('../services/orderService');
const { createStripeCheckoutSession } = require('../services/paymentService');
const { logAction } = require('../services/auditService');
const { PAYMENT_METHODS } = require('../utils/constants');

const placeOrder = asyncHandler(async (req, res) => {
  const order = await createOrder({ customerId: req.user._id, ...req.body });

  let checkout = null;
  if (order.paymentMethod === PAYMENT_METHODS.STRIPE) {
    checkout = await createStripeCheckoutSession(order);
  }

  res.status(201).json({ order, checkout });
});

const myOrders = asyncHandler(async (req, res) => {
  const orders = await Order.find({ customer: req.user._id }).sort({ createdAt: -1 });
  res.json({ orders });
});

const getMyOrder = asyncHandler(async (req, res) => {
  const order = await Order.findOne({ _id: req.params.id, customer: req.user._id });
  if (!order) throw new AppError(404, 'Order not found');
  res.json({ order });
});

// Admin/staff: all orders, optionally filtered by status.
const listOrders = asyncHandler(async (req, res) => {
  const { status, paymentStatus, page, limit } = req.query;
  const filter = {};
  if (status) filter.status = status;
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
  const order = await Order.findById(req.params.id).populate('customer', 'name email phone');
  if (!order) throw new AppError(404, 'Order not found');
  res.json({ order });
});

const changeOrderStatus = asyncHandler(async (req, res) => {
  const order = await updateOrderStatus({ orderId: req.params.id, ...req.body, actorId: req.user._id });
  await logAction({ actor: req.user._id, action: 'order.status_change', entityType: 'Order', entityId: order._id, details: req.body });
  res.json({ order });
});

module.exports = { placeOrder, myOrders, getMyOrder, listOrders, getOrder, changeOrderStatus };
