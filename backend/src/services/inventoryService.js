const Product = require('../models/Product');
const InventoryLog = require('../models/InventoryLog');
const AppError = require('../utils/AppError');

/**
 * Applies a stock delta to a product and records the movement as an
 * InventoryLog entry. currentStock is always derived from applying deltas,
 * never overwritten directly, so offline-synced sales reconcile safely.
 */
async function applyStockChange({ productId, delta, type, reference, reason, actor, branch }) {
  const product = await Product.findById(productId);
  if (!product) throw new AppError(404, `Product not found: ${productId}`);

  const resultingStock = product.currentStock + delta;
  if (!product.isMadeToOrder && resultingStock < 0) {
    throw new AppError(400, `Insufficient stock for ${product.name} (have ${product.currentStock}, need ${-delta})`);
  }

  product.currentStock = product.isMadeToOrder ? product.currentStock : resultingStock;
  await product.save();

  const log = await InventoryLog.create({
    product: product._id,
    type,
    quantityDelta: delta,
    resultingStock: product.currentStock,
    reference,
    reason,
    actor,
    branch,
  });

  return { product, log };
}

module.exports = { applyStockChange };
