const Order = require('../models/Order');
const Payment = require('../models/Payment');
const Product = require('../models/Product');
const AppError = require('../utils/AppError');
const env = require('../config/env');
const { applyStockChange } = require('./inventoryService');
const { pickBestPromotion } = require('./promotionService');
const { generateInvoiceNumber } = require('../utils/invoiceNumber');
const { domainEvents, EVENTS } = require('./events');
const User = require('../models/User');
const {
  INVENTORY_LOG_TYPES,
  JOB_STATUSES,
  ORDER_STATUSES,
  PAYMENT_METHODS,
  PAYMENT_STATUSES,
  TERMINAL_ORDER_STATUSES,
} = require('../utils/constants');

/**
 * Prices a cart without touching stock or creating anything. Shared by the
 * checkout summary (POST /orders/quote) and order creation so the customer
 * always confirms exactly the numbers that will be stored on the order.
 *
 * Each returned item is the snapshot that will live on the order: product
 * reference, name, SKU, barcode, image, unit price, quantity, line total.
 */
async function priceCart({ items, isHomeDelivery = true, taxRate }) {
  const products = await Product.find({ _id: { $in: items.map((i) => i.product) } });
  const productMap = new Map(products.map((p) => [p._id.toString(), p]));

  const orderItems = items.map(({ product: productId, quantity }) => {
    const product = productMap.get(productId);
    if (!product) throw new AppError(404, `Product not found: ${productId}`);
    if (!product.isActive || !product.isAvailableOnline) {
      throw new AppError(400, `${product.name} is not available for online ordering`);
    }
    if (!product.isMadeToOrder && product.currentStock < quantity) {
      throw new AppError(400, `Insufficient stock for ${product.name} (only ${product.currentStock} left)`);
    }
    const lineTotal = Number((product.price * quantity).toFixed(2));
    return {
      product: product._id,
      name: product.name,
      sku: product.sku,
      barcode: product.barcode,
      imageUrl: product.imageUrl,
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

  const effectiveTaxRate = taxRate === undefined ? env.orderTaxRate : taxRate;
  const taxableAmount = Number((subtotal - discountTotal).toFixed(2));
  const taxAmount = Number(((taxableAmount * effectiveTaxRate) / 100).toFixed(2));
  const deliveryFee = isHomeDelivery ? Number(env.deliveryFee || 0) : 0;
  const total = Number((taxableAmount + taxAmount + deliveryFee).toFixed(2));

  return {
    items: orderItems,
    productMap,
    promotion,
    subtotal,
    discountTotal,
    taxRate: effectiveTaxRate,
    taxAmount,
    deliveryFee,
    total,
  };
}

async function quoteOrder({ items, isHomeDelivery = true }) {
  const quote = await priceCart({ items, isHomeDelivery });
  return {
    items: quote.items,
    subtotal: quote.subtotal,
    discountTotal: quote.discountTotal,
    promotion: quote.promotion ? { id: quote.promotion._id, name: quote.promotion.name } : null,
    taxRate: quote.taxRate,
    taxAmount: quote.taxAmount,
    deliveryFee: quote.deliveryFee,
    total: quote.total,
  };
}

async function createOrder({ customerId, items, delivery, paymentMethod, taxRate }) {
  const isHomeDelivery = delivery?.isHomeDelivery !== false;
  const quote = await priceCart({ items, isHomeDelivery, taxRate });
  const orderNumber = generateInvoiceNumber('ORD');

  // Stock is reserved at placement so two customers can't both buy the last
  // unit; a cancelled order returns it (see updateOrderStatus).
  for (const item of quote.items) {
    const product = quote.productMap.get(item.product.toString());
    if (!product.isMadeToOrder) {
      await applyStockChange({
        productId: item.product,
        category: item.category,
        delta: -item.quantity,
        type: INVENTORY_LOG_TYPES.SALE,
        reference: orderNumber,
        reason: `Online order ${orderNumber} (reserved on placement)`,
        actor: customerId,
        branch: product.branch,
      });
    }
  }

  const order = new Order({
    orderNumber,
    customer: customerId,
    items: quote.items,
    subtotal: quote.subtotal,
    discountTotal: quote.discountTotal,
    promotion: quote.promotion ? quote.promotion._id : undefined,
    taxRate: quote.taxRate,
    taxAmount: quote.taxAmount,
    deliveryFee: quote.deliveryFee,
    total: quote.total,
    delivery,
    paymentMethod,
    paymentStatus: PAYMENT_STATUSES.UNPAID,
  });
  order.pushStatus(ORDER_STATUSES.PENDING, 'Order placed', customerId);
  await order.save();

  await Payment.create({
    order: order._id,
    method: paymentMethod,
    status: PAYMENT_STATUSES.UNPAID,
    amount: order.total,
  });

  // Spec §5: new online order → Admin + Staff on duty.
  const customer = await User.findById(customerId, 'name');
  domainEvents.emitSafe(EVENTS.ORDER_PLACED, {
    orderId: order._id,
    orderNumber: order.orderNumber,
    customerId,
    customerName: customer ? customer.name : undefined,
    total: order.total,
    itemCount: order.items.length,
    paymentMethod,
  });

  return order;
}

// Delivery sub-status mirrors the fulfilment stage so courier screens and
// customer tracking agree.
const DELIVERY_STATUS_FOR = {
  [ORDER_STATUSES.DISPATCHED]: 'dispatched',
  [ORDER_STATUSES.OUT_FOR_DELIVERY]: 'out_for_delivery',
  [ORDER_STATUSES.DELIVERED]: 'delivered',
  [ORDER_STATUSES.COMPLETED]: 'delivered',
};

async function restockOrderItems(order, actorId) {
  for (const item of order.items) {
    const product = await Product.findById(item.product);
    if (product && !product.isMadeToOrder) {
      await applyStockChange({
        productId: item.product,
        category: item.category,
        delta: item.quantity,
        type: INVENTORY_LOG_TYPES.RETURN,
        reference: order.orderNumber,
        reason: `Order ${order.orderNumber} cancelled`,
        actor: actorId,
        branch: product.branch,
      });
    }
  }
}

async function updateOrderStatus({ orderId, status, note, courierName, trackingNote, actorId }) {
  const order = await Order.findById(orderId);
  if (!order) throw new AppError(404, 'Order not found');
  if (TERMINAL_ORDER_STATUSES.includes(order.status)) {
    throw new AppError(400, `Order ${order.orderNumber} is already ${order.status} and cannot be changed`);
  }
  if (status === order.status) throw new AppError(400, `Order is already ${status}`);

  // Fulfilment can only start once the money side is settled: a manual
  // receipt must have been approved by an admin, a card payment confirmed by
  // Stripe, or the order is cash on delivery.
  const fulfilmentStatuses = [
    ORDER_STATUSES.CONFIRMED,
    ORDER_STATUSES.PROCESSING,
    ORDER_STATUSES.PACKING,
    ORDER_STATUSES.DISPATCHED,
    ORDER_STATUSES.OUT_FOR_DELIVERY,
    ORDER_STATUSES.DELIVERED,
    ORDER_STATUSES.COMPLETED,
  ];
  const paymentSettled =
    order.paymentMethod === PAYMENT_METHODS.CASH_ON_DELIVERY ||
    [PAYMENT_STATUSES.APPROVED, PAYMENT_STATUSES.PAID].includes(order.paymentStatus);
  if (fulfilmentStatuses.includes(status) && !paymentSettled) {
    throw new AppError(400, 'Payment has not been approved yet — review the receipt before processing this order');
  }

  order.pushStatus(status, note, actorId);
  if (DELIVERY_STATUS_FOR[status]) order.delivery.status = DELIVERY_STATUS_FOR[status];
  if (courierName) order.delivery.courierName = courierName;
  if (trackingNote) order.delivery.trackingNote = trackingNote;

  if ([ORDER_STATUSES.DELIVERED, ORDER_STATUSES.COMPLETED].includes(status)) {
    if (order.paymentMethod === PAYMENT_METHODS.CASH_ON_DELIVERY && order.paymentStatus !== PAYMENT_STATUSES.PAID) {
      order.paymentStatus = PAYMENT_STATUSES.PAID;
      await Payment.findOneAndUpdate({ order: order._id }, { status: PAYMENT_STATUSES.PAID });
    }
  }
  if (status === ORDER_STATUSES.CANCELLED) {
    order.delivery.status = 'failed';
    // Stock was reserved (decremented) at placement time; return it now that
    // the order will never be fulfilled. The terminal-status guard above
    // means a repeated cancel request can't double-restock.
    await restockOrderItems(order, actorId);
  }
  await order.save();

  domainEvents.emitSafe(EVENTS.ORDER_STATUS_CHANGED, {
    orderId: order._id,
    orderNumber: order.orderNumber,
    customerId: order.customer,
    status,
    note,
  });
  return order;
}

module.exports = { createOrder, quoteOrder, updateOrderStatus };
