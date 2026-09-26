const mongoose = require('mongoose');
const { PRODUCT_CATEGORIES } = require('../utils/constants');

const productSchema = new mongoose.Schema(
  {
    name: { type: String, required: true, trim: true },
    sku: { type: String, required: true, unique: true, trim: true, uppercase: true },
    category: {
      type: String,
      enum: Object.values(PRODUCT_CATEGORIES),
      required: true,
      index: true,
    },
    unit: { type: String, required: true, default: 'pcs' }, // pcs, ream, kg, dozen, etc.
    price: { type: Number, required: true, min: 0 },
    costPrice: { type: Number, required: true, min: 0, default: 0 },
    currentStock: { type: Number, required: true, default: 0 },
    reorderThreshold: { type: Number, required: true, default: 5 },
    isMadeToOrder: { type: Boolean, default: false }, // printing / garment-printing jobs
    isAvailableOnline: { type: Boolean, default: true },
    isActive: { type: Boolean, default: true },
    imageUrl: { type: String },
    description: { type: String, trim: true },
    branch: { type: String, trim: true },
  },
  { timestamps: true }
);

productSchema.index({ name: 'text', description: 'text' });
productSchema.virtual('isLowStock').get(function isLowStock() {
  return !this.isMadeToOrder && this.currentStock <= this.reorderThreshold;
});
productSchema.set('toJSON', { virtuals: true });
productSchema.set('toObject', { virtuals: true });

module.exports = mongoose.model('Product', productSchema);
