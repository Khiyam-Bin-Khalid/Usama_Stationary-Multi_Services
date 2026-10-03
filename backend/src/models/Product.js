const mongoose = require('mongoose');
const { DEFAULT_LOW_STOCK_THRESHOLD } = require('../utils/constants');

const productSchema = new mongoose.Schema(
  {
    name: { type: String, required: true, trim: true },
    // System-generated business identifier (skuService), e.g. STN-00001.
    // Distinct from the database Product ID (_id) and the physical barcode.
    sku: { type: String, required: true, unique: true, trim: true, uppercase: true },
    // Optional physical scan code (EAN/UPC/etc.), entered or scanned. Unique
    // when present; `sparse` lets many products have no barcode at all.
    barcode: { type: String, trim: true, unique: true, sparse: true },
    // Slug of a Category document (spec §4: categories → products → stock).
    // Existence is checked in the controller against the categories
    // collection so new categories can be added without a code change.
    category: { type: String, required: true, index: true, lowercase: true, trim: true },
    unit: { type: String, required: true, default: 'pcs' }, // pcs, ream, kg, dozen, etc.
    price: { type: Number, required: true, min: 0 },
    costPrice: { type: Number, required: true, min: 0, default: 0 },
    currentStock: { type: Number, required: true, default: 0 },
    reorderThreshold: { type: Number, required: true, default: DEFAULT_LOW_STOCK_THRESHOLD },
    isMadeToOrder: { type: Boolean, default: false }, // printing / garment-printing jobs
    isAvailableOnline: { type: Boolean, default: true },
    isActive: { type: Boolean, default: true },
    imageUrl: { type: String },
    description: { type: String, trim: true },
    branch: { type: String, trim: true },
    // Who added this product — lets Admin/Super Admin verify which staff
    // member entered it (desktop Inventory screen + audit log).
    createdBy: { type: mongoose.Schema.Types.ObjectId, ref: 'User' },
  },
  { timestamps: true }
);

productSchema.index({ name: 'text', description: 'text' });
productSchema.virtual('isLowStock').get(function isLowStock() {
  return !this.isMadeToOrder && this.currentStock > 0 && this.currentStock <= this.reorderThreshold;
});
// Spec §4.1: out-of-stock products are hidden from sellable lists (POS
// quick-sell + storefront) but never deleted — reports still reference them.
productSchema.virtual('isOutOfStock').get(function isOutOfStock() {
  return !this.isMadeToOrder && this.currentStock <= 0;
});
// Mongo filter for "currently sellable" — mirrors isOutOfStock.
productSchema.statics.sellableFilter = function sellableFilter() {
  return { isActive: true, $or: [{ isMadeToOrder: true }, { currentStock: { $gt: 0 } }] };
};
productSchema.set('toJSON', { virtuals: true });
productSchema.set('toObject', { virtuals: true });

module.exports = mongoose.model('Product', productSchema);
