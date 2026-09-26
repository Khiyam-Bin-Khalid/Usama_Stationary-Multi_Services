const Sale = require('../models/Sale');
const Product = require('../models/Product');
const AppError = require('../utils/AppError');
const { applyStockChange } = require('./inventoryService');
const { generateInvoiceNumber } = require('../utils/invoiceNumber');
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
async function createSale({ clientTxnId, items, paymentMethod, taxRate, branch, recordedOffline, cashierId }) {
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
        delta: -item.quantity,
        type: INVENTORY_LOG_TYPES.SALE,
        reference: clientTxnId,
        reason: 'POS sale',
        actor: cashierId,
        branch,
      });
    }
  }

  const sale = await Sale.create({
    clientTxnId,
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
  });

  return { sale, alreadyExisted: false };
}

module.exports = { createSale };
