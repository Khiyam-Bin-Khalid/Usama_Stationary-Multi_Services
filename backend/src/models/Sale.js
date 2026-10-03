const mongoose = require('mongoose');
const { JOB_STATUSES } = require('../utils/constants');

const saleItemSchema = new mongoose.Schema(
  {
    product: { type: mongoose.Schema.Types.ObjectId, ref: 'Product', required: true },
    name: { type: String, required: true }, // snapshot at time of sale
    sku: { type: String },
    imageUrl: { type: String },
    category: { type: String, required: true },
    unitPrice: { type: Number, required: true },
    quantity: { type: Number, required: true, min: 0.01 },
    lineTotal: { type: Number, required: true },
    jobStatus: { type: String, enum: Object.values(JOB_STATUSES), default: JOB_STATUSES.NONE },
  },
  { _id: false }
);

const saleSchema = new mongoose.Schema(
  {
    // Idempotency key generated client-side so an offline sale synced later
    // is never double-counted if the push is retried.
    clientTxnId: { type: String, required: true, unique: true, index: true },
    invoiceNumber: { type: String, required: true, unique: true },
    items: { type: [saleItemSchema], required: true, validate: (v) => v.length > 0 },
    subtotal: { type: Number, required: true },
    taxRate: { type: Number, required: true, default: 0 },
    taxAmount: { type: Number, required: true, default: 0 },
    total: { type: Number, required: true },
    paymentMethod: { type: String, enum: ['cash', 'card'], default: 'cash' },
    cashier: { type: mongoose.Schema.Types.ObjectId, ref: 'User', required: true, index: true },
    // Open shift of the cashier at the time of sale (spec §7 transactions.shift_id).
    shift: { type: mongoose.Schema.Types.ObjectId, ref: 'Shift', index: true },
    branch: { type: String, trim: true },
    // Set true when the record was created offline on the client and pushed later.
    recordedOffline: { type: Boolean, default: false },
    // FBR-ready fields (not wired to a live API yet — see plan)
    fbrInvoiceNumber: { type: String },
    fbrQrPayload: { type: String },
    fbrSyncStatus: { type: String, enum: ['not_applicable', 'pending', 'synced', 'failed'], default: 'not_applicable' },
  },
  { timestamps: true }
);

saleSchema.index({ createdAt: -1 });
saleSchema.index({ 'items.category': 1, createdAt: -1 });

module.exports = mongoose.model('Sale', saleSchema);
