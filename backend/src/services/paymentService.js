const path = require('path');
const Payment = require('../models/Payment');
const Order = require('../models/Order');
const AppError = require('../utils/AppError');
const stripeClient = require('./stripeClient');
const env = require('../config/env');
const { PAYMENT_METHODS, PAYMENT_STATUSES, ORDER_STATUSES } = require('../utils/constants');

async function createStripeCheckoutSession(order) {
  if (!stripeClient) {
    throw new AppError(
      503,
      'Stripe is not configured yet. Add STRIPE_SECRET_KEY to the backend .env, or choose manual receipt upload / cash on delivery instead.'
    );
  }

  const session = await stripeClient.checkout.sessions.create({
    mode: 'payment',
    payment_method_types: ['card'],
    line_items: order.items.map((item) => ({
      price_data: {
        currency: 'pkr',
        product_data: { name: item.name },
        unit_amount: Math.round(item.unitPrice * 100),
      },
      quantity: item.quantity,
    })),
    metadata: { orderId: order._id.toString(), orderNumber: order.orderNumber },
    success_url: `${env.clientOrigin}/orders/${order._id}?payment=success`,
    cancel_url: `${env.clientOrigin}/orders/${order._id}?payment=cancelled`,
  });

  await Payment.findOneAndUpdate(
    { order: order._id },
    { stripeSessionId: session.id, status: PAYMENT_STATUSES.PENDING_REVIEW }
  );

  return { checkoutUrl: session.url, sessionId: session.id };
}

async function handleStripeWebhook(rawBody, signature) {
  if (!stripeClient) throw new AppError(503, 'Stripe is not configured');

  let event;
  try {
    event = stripeClient.webhooks.constructEvent(rawBody, signature, env.stripe.webhookSecret);
  } catch (err) {
    throw new AppError(400, `Webhook signature verification failed: ${err.message}`);
  }

  if (event.type === 'checkout.session.completed') {
    const session = event.data.object;
    const orderId = session.metadata?.orderId;
    if (orderId) {
      await Payment.findOneAndUpdate(
        { order: orderId },
        { status: PAYMENT_STATUSES.PAID, stripePaymentIntentId: session.payment_intent }
      );
      const order = await Order.findById(orderId);
      if (order && order.status === ORDER_STATUSES.PENDING) {
        order.paymentStatus = PAYMENT_STATUSES.PAID;
        order.pushStatus(ORDER_STATUSES.CONFIRMED, 'Payment confirmed via Stripe');
        await order.save();
      }
    }
  }

  return { received: true };
}

async function attachReceiptUpload({ orderId, customerId, file }) {
  const order = await Order.findById(orderId);
  if (!order) throw new AppError(404, 'Order not found');
  if (!order.customer.equals(customerId)) throw new AppError(403, 'This order does not belong to you');
  if (order.paymentMethod !== PAYMENT_METHODS.MANUAL_RECEIPT) {
    throw new AppError(400, 'This order is not using manual receipt-upload payment');
  }

  const receiptImageUrl = `/uploads/${path.basename(file.path)}`;
  const payment = await Payment.findOneAndUpdate(
    { order: order._id },
    { receiptImageUrl, status: PAYMENT_STATUSES.PENDING_REVIEW },
    { new: true }
  );

  order.paymentStatus = PAYMENT_STATUSES.PENDING_REVIEW;
  await order.save();

  return payment;
}

async function reviewReceiptPayment({ paymentId, approve, reviewerId, note }) {
  const payment = await Payment.findById(paymentId);
  if (!payment) throw new AppError(404, 'Payment not found');
  if (payment.method !== PAYMENT_METHODS.MANUAL_RECEIPT) {
    throw new AppError(400, 'Only manual receipt-upload payments go through admin review');
  }

  payment.status = approve ? PAYMENT_STATUSES.PAID : PAYMENT_STATUSES.REJECTED;
  payment.reviewedBy = reviewerId;
  payment.reviewedAt = new Date();
  payment.reviewNote = note;
  await payment.save();

  const order = await Order.findById(payment.order);
  if (order) {
    order.paymentStatus = approve ? PAYMENT_STATUSES.PAID : PAYMENT_STATUSES.REJECTED;
    if (approve) {
      order.pushStatus(ORDER_STATUSES.CONFIRMED, 'Payment receipt approved');
    } else {
      order.pushStatus(ORDER_STATUSES.PENDING, `Payment receipt rejected: ${note || 'no reason given'}`);
    }
    await order.save();
  }

  return payment;
}

module.exports = {
  createStripeCheckoutSession,
  handleStripeWebhook,
  attachReceiptUpload,
  reviewReceiptPayment,
};
