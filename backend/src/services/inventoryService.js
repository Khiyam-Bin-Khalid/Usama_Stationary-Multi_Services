const Product = require('../models/Product');
const InventoryLog = require('../models/InventoryLog');
const AppError = require('../utils/AppError');
const { domainEvents, EVENTS } = require('./events');
const { logAction } = require('./auditService');

/**
 * Applies a stock delta to a product and records the movement as an
 * InventoryLog entry. currentStock is always derived from applying deltas,
 * never overwritten directly, so offline-synced sales reconcile safely.
 *
 * Every movement row carries: product, SKU, previous stock, quantity changed,
 * resulting stock, movement type, related sale/order reference, responsible
 * user and timestamp (consolidated spec, "inventory movement record").
 *
 * Spec §4.1 rules implemented here:
 *  1. Stock is decremented within its specific category — callers pass the
 *     category they believe the product belongs to and a mismatch is
 *     rejected, so a sale can never touch stock in another category.
 *  2. Reaching 0 marks the product out of stock (hidden from sellable
 *     lists via `isOutOfStock`, never deleted) and emits OUT_OF_STOCK.
 *  3. Crossing down to <= reorderThreshold emits LOW_STOCK.
 *  4. Both events are audit-logged as well as notified.
 */
async function applyStockChange({ productId, category, delta, type, reference, reason, actor, actorRole, branch }) {
  const product = await Product.findById(productId);
  if (!product) throw new AppError(404, `Product not found: ${productId}`);
  if (category && product.category !== category) {
    throw new AppError(400, `${product.name} belongs to category "${product.category}", not "${category}"`);
  }

  const previousStock = product.currentStock;
  const resultingStock = previousStock + delta;
  if (!product.isMadeToOrder && resultingStock < 0) {
    throw new AppError(400, `Insufficient stock for ${product.name} (have ${product.currentStock}, need ${-delta})`);
  }

  product.currentStock = product.isMadeToOrder ? product.currentStock : resultingStock;
  await product.save();

  const log = await InventoryLog.create({
    product: product._id,
    productName: product.name,
    sku: product.sku,
    category: product.category,
    type,
    previousStock,
    quantityDelta: delta,
    resultingStock: product.currentStock,
    reference,
    reason,
    actor,
    branch,
  });

  if (!product.isMadeToOrder && delta < 0) {
    await emitStockThresholdEvents({ product, previousStock, actor, actorRole });
  }

  return { product, log };
}

async function emitStockThresholdEvents({ product, previousStock, actor, actorRole }) {
  const base = {
    productId: product._id,
    productName: product.name,
    sku: product.sku,
    category: product.category,
    unit: product.unit,
    currentStock: product.currentStock,
    reorderThreshold: product.reorderThreshold,
  };

  if (product.currentStock === 0 && previousStock > 0) {
    await logAction({
      actor,
      actorRole,
      action: 'inventory.out_of_stock',
      entityType: 'Product',
      entityId: product._id,
      before: { currentStock: previousStock },
      after: { currentStock: 0 },
    });
    domainEvents.emitSafe(EVENTS.OUT_OF_STOCK, base);
    return;
  }

  const crossedThreshold = previousStock > product.reorderThreshold && product.currentStock <= product.reorderThreshold;
  if (crossedThreshold && product.currentStock > 0) {
    await logAction({
      actor,
      actorRole,
      action: 'inventory.low_stock',
      entityType: 'Product',
      entityId: product._id,
      before: { currentStock: previousStock },
      after: { currentStock: product.currentStock, reorderThreshold: product.reorderThreshold },
    });
    domainEvents.emitSafe(EVENTS.LOW_STOCK, base);
  }
}

// Stock-movement history across all products (Admin "Stock movement" screen).
async function listMovements({ product, sku, category, type, from, to, page = 1, limit = 50 }) {
  const filter = {};
  if (product) filter.product = product;
  if (sku) filter.sku = sku.toUpperCase();
  if (category) filter.category = category;
  if (type) filter.type = type;
  if (from || to) {
    filter.createdAt = {};
    if (from) filter.createdAt.$gte = new Date(from);
    if (to) filter.createdAt.$lte = new Date(to);
  }
  const total = await InventoryLog.countDocuments(filter);
  const logs = await InventoryLog.find(filter)
    .sort({ createdAt: -1 })
    .skip((page - 1) * limit)
    .limit(limit)
    .populate('actor', 'name role')
    .populate('product', 'name sku barcode imageUrl unit');
  return { logs, total, page, limit };
}

// Products at or below their reorder level (plus out-of-stock), for the
// Admin "Low stock" screen and the dashboard counter.
function lowStockProducts() {
  return Product.find({ isActive: true, isMadeToOrder: false, $expr: { $lte: ['$currentStock', '$reorderThreshold'] } })
    .sort({ currentStock: 1, name: 1 })
    .populate('createdBy', 'name role');
}

module.exports = { applyStockChange, listMovements, lowStockProducts };
