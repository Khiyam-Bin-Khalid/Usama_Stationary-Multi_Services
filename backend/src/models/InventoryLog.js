const mongoose = require('mongoose');
const { INVENTORY_LOG_TYPES } = require('../utils/constants');

const inventoryLogSchema = new mongoose.Schema(
  {
    product: { type: mongoose.Schema.Types.ObjectId, ref: 'Product', required: true, index: true },
    type: { type: String, enum: Object.values(INVENTORY_LOG_TYPES), required: true },
    quantityDelta: { type: Number, required: true }, // positive = stock in, negative = stock out
    resultingStock: { type: Number, required: true },
    reference: { type: String }, // e.g. Sale id, Order id, manual note
    reason: { type: String },
    actor: { type: mongoose.Schema.Types.ObjectId, ref: 'User', required: true },
    branch: { type: String, trim: true },
  },
  { timestamps: true }
);

inventoryLogSchema.index({ product: 1, createdAt: -1 });

module.exports = mongoose.model('InventoryLog', inventoryLogSchema);
