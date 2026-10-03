const mongoose = require('mongoose');
const { SHIFT_STATUSES } = require('../utils/constants');

// Spec §6 / §7 `shifts`: cash-drawer reconciliation. A staff member opens a
// shift with a starting float and closes it with the counted cash; the
// expected figure is computed from the cash sales attached to the shift.
const shiftSchema = new mongoose.Schema(
  {
    staff: { type: mongoose.Schema.Types.ObjectId, ref: 'User', required: true, index: true },
    branch: { type: String, trim: true },
    status: { type: String, enum: Object.values(SHIFT_STATUSES), default: SHIFT_STATUSES.OPEN, index: true },
    openingCash: { type: Number, required: true, min: 0, default: 0 },
    closingCashExpected: { type: Number },
    closingCashActual: { type: Number },
    cashVariance: { type: Number },
    salesCount: { type: Number, default: 0 },
    salesTotal: { type: Number, default: 0 },
    cashSalesTotal: { type: Number, default: 0 },
    cardSalesTotal: { type: Number, default: 0 },
    note: { type: String, trim: true },
    openedAt: { type: Date, default: Date.now },
    closedAt: { type: Date },
  },
  { timestamps: true }
);

// One open shift per staff member at a time.
shiftSchema.index({ staff: 1, status: 1 });

module.exports = mongoose.model('Shift', shiftSchema);
