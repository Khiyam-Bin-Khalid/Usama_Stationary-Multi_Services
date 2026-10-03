const mongoose = require('mongoose');
const { ORDER_STATUSES, PAYMENT_METHODS, PAYMENT_STATUSES, JOB_STATUSES } = require('../utils/constants');

// Each line keeps a snapshot of the product as the customer saw it (name,
// SKU, image, price). The image reference therefore survives the whole order
// lifecycle even if the catalog product is later edited, re-photographed or
// soft-deleted — the customer and admin always see the item that was ordered.
const orderItemSchema = new mongoose.Schema(
  {
    product: { type: mongoose.Schema.Types.ObjectId, ref: 'Product', required: true },
    name: { type: String, required: true },
    sku: { type: String },
    barcode: { type: String },
    imageUrl: { type: String },
    category: { type: String, required: true },
    unitPrice: { type: Number, required: true },
    quantity: { type: Number, required: true, min: 1 },
    lineTotal: { type: Number, required: true },
    jobStatus: { type: String, enum: Object.values(JOB_STATUSES), default: JOB_STATUSES.NONE },
  },
  { _id: false }
);

const statusEventSchema = new mongoose.Schema(
  {
    status: { type: String, enum: Object.values(ORDER_STATUSES), required: true },
    at: { type: Date, default: Date.now },
    note: { type: String },
    by: { type: mongoose.Schema.Types.ObjectId, ref: 'User' },
  },
  { _id: false }
);

const orderSchema = new mongoose.Schema(
  {
    orderNumber: { type: String, required: true, unique: true },
    customer: { type: mongoose.Schema.Types.ObjectId, ref: 'User', required: true, index: true },
    items: { type: [orderItemSchema], required: true, validate: (v) => v.length > 0 },
    subtotal: { type: Number, required: true },
    discountTotal: { type: Number, required: true, default: 0 },
    promotion: { type: mongoose.Schema.Types.ObjectId, ref: 'Promotion' },
    taxRate: { type: Number, required: true, default: 0 },
    taxAmount: { type: Number, required: true, default: 0 },
    deliveryFee: { type: Number, required: true, default: 0 },
    total: { type: Number, required: true },

    delivery: {
      isHomeDelivery: { type: Boolean, default: true },
      address: {
        line1: String,
        line2: String,
        city: String,
        phone: String,
      },
      window: { type: String }, // e.g. "2026-09-27 14:00-17:00"
      status: {
        type: String,
        enum: ['pending', 'assigned', 'dispatched', 'out_for_delivery', 'delivered', 'failed'],
        default: 'pending',
      },
      courierName: { type: String },
      trackingNote: { type: String },
    },

    paymentMethod: { type: String, enum: Object.values(PAYMENT_METHODS), required: true },
    paymentStatus: {
      type: String,
      enum: Object.values(PAYMENT_STATUSES),
      required: true,
      default: PAYMENT_STATUSES.UNPAID,
    },

    status: { type: String, enum: Object.values(ORDER_STATUSES), default: ORDER_STATUSES.PENDING },
    statusHistory: { type: [statusEventSchema], default: [] },

    // FBR-ready fields
    fbrInvoiceNumber: { type: String },
    fbrQrPayload: { type: String },
    fbrSyncStatus: { type: String, enum: ['not_applicable', 'pending', 'synced', 'failed'], default: 'not_applicable' },
  },
  { timestamps: true }
);

orderSchema.index({ createdAt: -1 });
orderSchema.index({ status: 1, createdAt: -1 });

orderSchema.methods.pushStatus = function pushStatus(status, note, by) {
  this.status = status;
  this.statusHistory.push({ status, note, by, at: new Date() });
};

module.exports = mongoose.model('Order', orderSchema);
