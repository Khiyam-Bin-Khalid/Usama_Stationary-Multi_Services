const Sale = require('../models/Sale');
const Product = require('../models/Product');
const AppError = require('../utils/AppError');
const { applyStockChange } = require('./inventoryService');
const { generateInvoiceNumber } = require('../utils/invoiceNumber');
const { currentOpenShift } = require('./shiftService');
const { INVENTORY_LOG_TYPES, JOB_STATUSES } = require('../utils/constants');

/**
 * Creates a POS sale. Idempotent by clientTxnId so a sale queued offline and
 * pushed more than once (retry after a dropped connection) is never double-
 * counted — a repeat call just returns the already-recorded sale.
 *
 * Note: without a MongoDB replica set there is no multi-document transaction
 * available, so stock sufficiency is checked up-front for all items before
 * any stock is decremented. This narrows, but does not eliminate, the race
 * window under concurrent sales of the same item — acceptable for a single
 * counter/branch deployment; revisit with transactions if scaling to a
 * multi-terminal, high-concurrency setup.
 */
async function createSale({ clientTxnId, items, paymentMethod, taxRate, branch, recordedOffline, cashierId, cashierRole, soldAt }) {
  const existing = await Sale.findOne({ clientTxnId });
  if (existing) return { sale: existing, alreadyExisted: true };

  const products = await Product.find({ _id: { $in: items.map((i) => i.product) } });
  const productMap = new Map(products.map((p) => [p._id.toString(), p]));

  const saleItems = items.map(({ product: productId, quantity }) => {
    const product = productMap.get(productId);
    if (!product) throw new AppError(404, `Product not found: ${productId}`);
    if (!product.isMadeToOrder && product.currentStock < quantity) {
      throw new AppError(400, `Insufficient stock for ${product.name} (have ${product.currentStock}, need ${quantity})`);
    }
    const lineTotal = Number((product.price * quantity).toFixed(2));
    return {
      product: product._id,
      name: product.name,
      sku: product.sku,
      imageUrl: product.imageUrl,
      category: product.category,
      unitPrice: product.price,
      quantity,
      lineTotal,
      jobStatus: product.isMadeToOrder ? JOB_STATUSES.QUEUED : JOB_STATUSES.NONE,
    };
  });

  const subtotal = Number(saleItems.reduce((sum, i) => sum + i.lineTotal, 0).toFixed(2));
  const taxAmount = Number(((subtotal * taxRate) / 100).toFixed(2));
  const total = Number((subtotal + taxAmount).toFixed(2));

  for (const item of saleItems) {
    const product = productMap.get(item.product.toString());
    if (!product.isMadeToOrder) {
      await applyStockChange({
        productId: item.product,
        category: item.category, // spec §4.1: decrement within the product's own category
        delta: -item.quantity,
        type: INVENTORY_LOG_TYPES.SALE,
        reference: clientTxnId,
        reason: 'POS sale',
        actor: cashierId,
        actorRole: cashierRole,
        branch,
      });
    }
  }

  // Offline sales keep the time they really happened so they count on the
  // right day in reports. A device clock ahead of the server can't date a
  // sale in the future.
  const now = new Date();
  const saleTime = soldAt && new Date(soldAt) < now ? new Date(soldAt) : now;

  // Only attach to the open shift if the sale happened during it; a sale from
  // before this shift opened must not land in this drawer's cash count.
  const openShift = await currentOpenShift(cashierId);
  const shift = openShift && openShift.openedAt <= saleTime ? openShift : null;

  const sale = await Sale.create({
    clientTxnId,
    shift: shift ? shift._id : undefined,
    invoiceNumber: generateInvoiceNumber('INV'),
    items: saleItems,
    subtotal,
    taxRate,
    taxAmount,
    total,
    paymentMethod,
    cashier: cashierId,
    branch,
    recordedOffline: Boolean(recordedOffline),
    createdAt: saleTime,
  });

  return { sale, alreadyExisted: false };
}

module.exports = { createSale };
