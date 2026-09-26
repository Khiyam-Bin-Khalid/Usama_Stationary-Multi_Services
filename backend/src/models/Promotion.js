const mongoose = require('mongoose');
const { PRODUCT_CATEGORIES } = require('../utils/constants');

const promotionSchema = new mongoose.Schema(
  {
    name: { type: String, required: true, trim: true },
    description: { type: String, trim: true },
    discountType: { type: String, enum: ['percent', 'flat'], required: true },
    discountValue: { type: Number, required: true, min: 0 },
    categories: [{ type: String, enum: Object.values(PRODUCT_CATEGORIES) }],
    products: [{ type: mongoose.Schema.Types.ObjectId, ref: 'Product' }],
    startDate: { type: Date, required: true },
    endDate: { type: Date, required: true },
    isActive: { type: Boolean, default: true },
    createdBy: { type: mongoose.Schema.Types.ObjectId, ref: 'User', required: true },
  },
  { timestamps: true }
);

promotionSchema.methods.appliesTo = function appliesTo(product) {
  const now = new Date();
  if (!this.isActive || now < this.startDate || now > this.endDate) return false;
  if (this.products.length && this.products.some((p) => p.equals(product._id))) return true;
  if (this.categories.length && this.categories.includes(product.category)) return true;
  return false;
};

promotionSchema.methods.discountFor = function discountFor(price) {
  if (this.discountType === 'percent') return (price * this.discountValue) / 100;
  return Math.min(this.discountValue, price);
};

module.exports = mongoose.model('Promotion', promotionSchema);
