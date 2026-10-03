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
    note: req.body ? req.body.note : undefined,
  });
  res.json({ payment });
});

// Receipts awaiting an explicit admin decision. The populated order carries
// the item snapshots (images, SKUs, quantities) so the reviewer sees the
// complete order next to the receipt.
const listPendingReview = asyncHandler(async (req, res) => {
  const payments = await Payment.find({
    method: PAYMENT_METHODS.MANUAL_RECEIPT,
    status: PAYMENT_STATUSES.PENDING_REVIEW,
  })
    .sort({ receiptUploadedAt: 1, createdAt: 1 })
    .populate({ path: 'order', populate: { path: 'customer', select: 'name email phone' } });

  res.json({ payments });
});

// Payment (incl. receipt + review outcome) for one order — admin order detail.
const getOrderPayment = asyncHandler(async (req, res) => {
  const payment = await Payment.findOne({ order: req.params.orderId }).populate('reviewedBy', 'name role');
  if (!payment) throw new AppError(404, 'Payment not found');
  res.json({ payment });
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

module.exports = { stripeWebhook, uploadReceipt, listPendingReview, getOrderPayment, reviewPayment };
