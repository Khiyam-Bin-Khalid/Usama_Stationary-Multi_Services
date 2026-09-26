const mongoose = require('mongoose');
const { PAYMENT_METHODS, PAYMENT_STATUSES } = require('../utils/constants');

const paymentSchema = new mongoose.Schema(
  {
    order: { type: mongoose.Schema.Types.ObjectId, ref: 'Order', required: true, index: true },
    method: { type: String, enum: Object.values(PAYMENT_METHODS), required: true },
    status: {
      type: String,
      enum: Object.values(PAYMENT_STATUSES),
      required: true,
      default: PAYMENT_STATUSES.UNPAID,
    },
    amount: { type: Number, required: true },

    // Stripe
    stripeSessionId: { type: String },
    stripePaymentIntentId: { type: String },

    // Manual receipt upload
    receiptImageUrl: { type: String },
    receiptNote: { type: String },

    // Admin review (manual_receipt method)
    reviewedBy: { type: mongoose.Schema.Types.ObjectId, ref: 'User' },
    reviewedAt: { type: Date },
    reviewNote: { type: String },
  },
  { timestamps: true }
);

module.exports = mongoose.model('Payment', paymentSchema);
