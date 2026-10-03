const mongoose = require('mongoose');
const { DISCREPANCY_STATUSES } = require('../utils/constants');

// Spec §2 / §3.3: staff can *report* that the shelf count doesn't match the
// system, but cannot change stock themselves. Admin/Super Admin resolve the
// report and (optionally) apply the correcting adjustment.
const discrepancyReportSchema = new mongoose.Schema(
  {
    product: { type: mongoose.Schema.Types.ObjectId, ref: 'Product', required: true, index: true },
    category: { type: String, required: true },
    productName: { type: String, required: true },
    systemQty: { type: Number, required: true },
    countedQty: { type: Number, required: true, min: 0 },
    note: { type: String, trim: true, maxlength: 500 },
    reportedBy: { type: mongoose.Schema.Types.ObjectId, ref: 'User', required: true, index: true },
    status: { type: String, enum: Object.values(DISCREPANCY_STATUSES), default: DISCREPANCY_STATUSES.OPEN, index: true },
    resolvedBy: { type: mongoose.Schema.Types.ObjectId, ref: 'User' },
    resolvedAt: { type: Date },
    resolution: { type: String, trim: true, maxlength: 500 },
    adjustmentApplied: { type: Number }, // stock delta applied on resolution, if any
  },
  { timestamps: true }
);

discrepancyReportSchema.virtual('difference').get(function difference() {
  return this.countedQty - this.systemQty;
});
discrepancyReportSchema.set('toJSON', { virtuals: true });
discrepancyReportSchema.set('toObject', { virtuals: true });

module.exports = mongoose.model('DiscrepancyReport', discrepancyReportSchema);
