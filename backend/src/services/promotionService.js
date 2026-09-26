const Promotion = require('../models/Promotion');

/**
 * Evaluates every currently-active promotion against the cart and returns
 * the one that yields the largest total discount (SRS models promotions as
 * seasonal storewide/category deals, not stackable promo codes, so exactly
 * one is applied per order).
 */
async function pickBestPromotion(items, products) {
  const now = new Date();
  const activePromotions = await Promotion.find({ isActive: true, startDate: { $lte: now }, endDate: { $gte: now } });
  if (!activePromotions.length) return { promotion: null, discountTotal: 0 };

  let best = { promotion: null, discountTotal: 0 };
  for (const promotion of activePromotions) {
    let discount = 0;
    for (const { productId, quantity, lineTotal } of items) {
      const product = products.get(productId);
      if (promotion.appliesTo(product)) {
        discount += promotion.discountFor(lineTotal / quantity) * quantity;
      }
    }
    if (discount > best.discountTotal) best = { promotion, discountTotal: Number(discount.toFixed(2)) };
  }
  return best;
}

module.exports = { pickBestPromotion };
