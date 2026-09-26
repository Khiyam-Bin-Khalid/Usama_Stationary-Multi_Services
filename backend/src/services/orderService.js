const Order = require('../models/Order');
const Payment = require('../models/Payment');
const Product = require('../models/Product');
const AppError = require('../utils/AppError');
const { applyStockChange } = require('./inventoryService');
const { pickBestPromotion } = require('./promotionService');
const { generateInvoiceNumber } = require('../utils/invoiceNumber');
const { INVENTORY_LOG_TYPES, JOB_STATUSES, ORDER_STATUSES, PAYMENT_METHODS, PAYMENT_STATUSES } = require('../utils/constants');

async function createOrder({ customerId, items, delivery, paymentMethod, taxRate = 0 }) {
  const products = await Product.find({ _id: { $in: items.map((i) => i.product) } });
  const productMap = new Map(products.map((p) => [p._id.toString(), p]));

  const orderItems = items.map(({ product: productId, quantity }) => {
    const product = productMap.get(productId);
    if (!product) throw new AppError(404, `Product not found: ${productId}`);
    if (!product.isActive || !product.isAvailableOnline) {
      throw new AppError(400, `${product.name} is not available for online ordering`);
    }
    if (!product.isMadeToOrder && product.currentStock < quantity) {
      throw new AppError(400, `Insufficient stock for ${product.name}`);
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

  const subtotal = Number(orderItems.reduce((sum, i) => sum + i.lineTotal, 0).toFixed(2));

  const { promotion, discountTotal } = await pickBestPromotion(
    orderItems.map((i) => ({ productId: i.product.toString(), quantity: i.quantity, lineTotal: i.lineTotal })),
    productMap
  );

  const taxableAmount = subtotal - discountTotal;
  const taxAmount = Number(((taxableAmount * taxRate) / 100).toFixed(2));
  const deliveryFee = 0; // not specified by SRS; kept as an explicit, extendable field
  const total = Number((taxableAmount + taxAmount + deliveryFee).toFixed(2));

  for (const item of orderItems) {
    const product = productMap.get(item.product.toString());
    if (!product.isMadeToOrder) {
      await applyStockChange({
        productId: item.product,
        delta: -item.quantity,
        type: INVENTORY_LOG_TYPES.SALE,
        reference: 'pending-order',
        reason: 'Online order (reserved on placement)',
        actor: customerId,
        branch: product.branch,
      });
    }
  }

  const order = new Order({
    orderNumber: generateInvoiceNumber('ORD'),
    customer: customerId,
    items: orderItems,
    subtotal,
    discountTotal,
    promotion: promotion ? promotion._id : undefined,
    taxRate,
    taxAmount,
    deliveryFee,
    total,
    delivery,
    paymentMethod,
    paymentStatus: PAYMENT_STATUSES.UNPAID,
  });
  order.pushStatus(ORDER_STATUSES.PENDING, 'Order placed');
  await order.save();

  await Payment.create({
    order: order._id,
    method: paymentMethod,
    status: PAYMENT_STATUSES.UNPAID,
    amount: order.total,
  });

  return order;
}

async function updateOrderStatus({ orderId, status, note, actorId }) {
  const order = await Order.findById(orderId);
  if (!order) throw new AppError(404, 'Order not found');
  const wasAlreadyCancelled = order.status === ORDER_STATUSES.CANCELLED;

  order.pushStatus(status, note);
  if (status === ORDER_STATUSES.OUT_FOR_DELIVERY) order.delivery.status = 'out_for_delivery';
  if (status === ORDER_STATUSES.DELIVERED) {
    order.delivery.status = 'delivered';
    if (order.paymentMethod === PAYMENT_METHODS.CASH_ON_DELIVERY) {
      order.paymentStatus = PAYMENT_STATUSES.PAID;
      await Payment.findOneAndUpdate({ order: order._id }, { status: PAYMENT_STATUSES.PAID });
    }
  }
  if (status === ORDER_STATUSES.CANCELLED && !wasAlreadyCancelled) {
    // Stock was reserved (decremented) at placement time; return it now that
    // the order will never be fulfilled. Guarded by wasAlreadyCancelled so a
    // repeated cancel request can't double-restock.
    for (const item of order.items) {
      const product = await Product.findById(item.product);
      if (product && !product.isMadeToOrder) {
        await applyStockChange({
          productId: item.product,
          delta: item.quantity,
          type: INVENTORY_LOG_TYPES.RETURN,
          reference: order._id.toString(),
          reason: `Order ${order.orderNumber} cancelled`,
          actor: actorId,
          branch: product.branch,
        });
      }
    }
  }
  await order.save();
  return order;
}

module.exports = { createOrder, updateOrderStatus };
