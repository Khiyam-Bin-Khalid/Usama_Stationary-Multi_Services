const Payment = require('../models/Payment');
const AppError = require('../utils/AppError');
const asyncHandler = require('../utils/asyncHandler');
const {
  handleStripeWebhook,
  attachReceiptUpload,
  reviewReceiptPayment,
} = require('../services/paymentService');
const { logAction } = require('../services/auditService');
const { PAYMENT_METHODS, PAYMENT_STATUSES } = require('../utils/constants');

const stripeWebhook = asyncHandler(async (req, res) => {
  const signature = req.headers['stripe-signature'];
  const result = await handleStripeWebhook(req.body, signature);
  res.json(result);
});

const uploadReceipt = asyncHandler(async (req, res) => {
  if (!req.file) throw new AppError(400, 'No receipt file uploaded');
  const payment = await attachReceiptUpload({
    orderId: req.params.orderId,
    customerId: req.user._id,
    file: req.file,
  });
  res.json({ payment });
});

const listPendingReview = asyncHandler(async (req, res) => {
  const payments = await Payment.find({
    method: PAYMENT_METHODS.MANUAL_RECEIPT,
    status: PAYMENT_STATUSES.PENDING_REVIEW,
  })
    .sort({ createdAt: 1 })
    .populate({ path: 'order', populate: { path: 'customer', select: 'name email phone' } });

  res.json({ payments });
});

const reviewPayment = asyncHandler(async (req, res) => {
  const { approve, note } = req.body;
  const payment = await reviewReceiptPayment({
    paymentId: req.params.id,
    approve,
    reviewerId: req.user._id,
    note,
  });

  await logAction({
    actor: req.user._id,
    action: approve ? 'payment.approve' : 'payment.reject',
    entityType: 'Payment',
    entityId: payment._id,
    details: { note },
  });

  res.json({ payment });
});

module.exports = { stripeWebhook, uploadReceipt, listPendingReview, reviewPayment };
