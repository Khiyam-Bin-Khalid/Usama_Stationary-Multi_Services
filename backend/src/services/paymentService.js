const path = require('path');
const Payment = require('../models/Payment');
const Order = require('../models/Order');
const AppError = require('../utils/AppError');
const stripeClient = require('./stripeClient');
const env = require('../config/env');
const { PAYMENT_METHODS, PAYMENT_STATUSES, ORDER_STATUSES } = require('../utils/constants');
const { domainEvents, EVENTS } = require('./events');

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
        product_data: { name: item.name, ...(item.sku ? { description: `SKU ${item.sku}` } : {}) },
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
  const fresh = await Order.findById(order._id);
  if (fresh && fresh.status === ORDER_STATUSES.PENDING) {
    fresh.paymentStatus = PAYMENT_STATUSES.PENDING_REVIEW;
    fresh.pushStatus(ORDER_STATUSES.PAYMENT_SUBMITTED, 'Card checkout started (Stripe)');
    await fresh.save();
  }

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
      if (order && [ORDER_STATUSES.PENDING, ORDER_STATUSES.PAYMENT_SUBMITTED].includes(order.status)) {
        order.paymentStatus = PAYMENT_STATUSES.PAID;
        order.pushStatus(ORDER_STATUSES.PAYMENT_APPROVED, 'Card payment confirmed by Stripe');
        order.pushStatus(ORDER_STATUSES.CONFIRMED, 'Order confirmed');
        await order.save();
        domainEvents.emitSafe(EVENTS.PAYMENT_APPROVED, {
          orderId: order._id,
          orderNumber: order.orderNumber,
          customerId: order.customer,
          method: PAYMENT_METHODS.STRIPE,
        });
      }
    }
  }

  // Spec §5: failed online payment → Admin (in-app + email).
  if (event.type === 'checkout.session.async_payment_failed' || event.type === 'checkout.session.expired') {
    const session = event.data.object;
    const orderId = session.metadata?.orderId;
    if (orderId) {
      await Payment.findOneAndUpdate({ order: orderId }, { status: PAYMENT_STATUSES.FAILED });
      const order = await Order.findByIdAndUpdate(orderId, { paymentStatus: PAYMENT_STATUSES.FAILED }, { new: true });
      domainEvents.emitSafe(EVENTS.PAYMENT_FAILED, {
        orderId,
        orderNumber: order ? order.orderNumber : orderId,
        reason: event.type === 'checkout.session.expired' ? 'checkout session expired' : 'card payment failed',
      });
    }
  }

  return { received: true };
}

/**
 * Customer uploads a payment receipt / proof. The receipt is attached to
 * the order's Payment and the order moves to Payment Submitted → Payment
 * Under Review. Nothing is approved automatically: only reviewReceiptPayment
 * (an explicit admin action) can move it further.
 *
 * Allowed while the payment is unpaid, or after a rejection (re-upload with
 * the corrected proof).
 */
async function attachReceiptUpload({ orderId, customerId, file, note }) {
  const order = await Order.findById(orderId);
  if (!order) throw new AppError(404, 'Order not found');
  if (!order.customer.equals(customerId)) throw new AppError(403, 'This order does not belong to you');
  if (order.paymentMethod !== PAYMENT_METHODS.MANUAL_RECEIPT) {
    throw new AppError(400, 'This order is not using manual receipt-upload payment');
  }
  if ([ORDER_STATUSES.CANCELLED, ORDER_STATUSES.COMPLETED].includes(order.status)) {
    throw new AppError(400, `Order ${order.orderNumber} is ${order.status}; a receipt can no longer be uploaded`);
  }
  if ([PAYMENT_STATUSES.APPROVED, PAYMENT_STATUSES.PAID].includes(order.paymentStatus)) {
    throw new AppError(400, 'This payment has already been approved');
  }

  const receiptImageUrl = `/uploads/${path.basename(file.path)}`;
  const payment = await Payment.findOneAndUpdate(
    { order: order._id },
    {
      receiptImageUrl,
      receiptNote: note,
      receiptUploadedAt: new Date(),
      status: PAYMENT_STATUSES.PENDING_REVIEW,
      $unset: { reviewedBy: 1, reviewedAt: 1, reviewNote: 1 },
    },
    { new: true }
  );

  const isResubmission = order.paymentStatus === PAYMENT_STATUSES.REJECTED;
  order.paymentStatus = PAYMENT_STATUSES.PENDING_REVIEW;
  order.pushStatus(
    ORDER_STATUSES.PAYMENT_SUBMITTED,
    isResubmission ? 'Corrected payment receipt uploaded' : 'Payment receipt uploaded',
    customerId
  );
  order.pushStatus(ORDER_STATUSES.PAYMENT_UNDER_REVIEW, 'Awaiting admin verification of the receipt');
  await order.save();

  // Consolidated spec: admin is notified that a receipt needs review.
  domainEvents.emitSafe(EVENTS.PAYMENT_REVIEW_REQUIRED, {
    orderId: order._id,
    orderNumber: order.orderNumber,
    paymentId: payment._id,
    amount: payment.amount,
    isResubmission,
  });

  return payment;
}

/**
 * Explicit admin decision on an uploaded receipt. Approve → payment Approved,
 * order Payment Approved → Confirmed (fulfilment can start). Reject → payment
 * Rejected, order Payment Rejected, customer notified so they can re-upload.
 */
async function reviewReceiptPayment({ paymentId, approve, reviewerId, note }) {
  const payment = await Payment.findById(paymentId);
  if (!payment) throw new AppError(404, 'Payment not found');
  if (payment.method !== PAYMENT_METHODS.MANUAL_RECEIPT) {
    throw new AppError(400, 'Only manual receipt-upload payments go through admin review');
  }
  if (!payment.receiptImageUrl) throw new AppError(400, 'No receipt has been uploaded for this payment yet');
  if (payment.status !== PAYMENT_STATUSES.PENDING_REVIEW) {
    throw new AppError(400, `This payment is already ${payment.status}`);
  }

  payment.status = approve ? PAYMENT_STATUSES.APPROVED : PAYMENT_STATUSES.REJECTED;
  payment.reviewedBy = reviewerId;
  payment.reviewedAt = new Date();
  payment.reviewNote = note;
  await payment.save();

  const order = await Order.findById(payment.order);
  if (order) {
    order.paymentStatus = payment.status;
    if (approve) {
      order.pushStatus(ORDER_STATUSES.PAYMENT_APPROVED, note ? `Receipt approved: ${note}` : 'Payment receipt approved', reviewerId);
      order.pushStatus(ORDER_STATUSES.CONFIRMED, 'Order confirmed', reviewerId);
    } else {
      order.pushStatus(ORDER_STATUSES.PAYMENT_REJECTED, `Payment receipt rejected: ${note || 'no reason given'}`, reviewerId);
    }
    await order.save();

    domainEvents.emitSafe(approve ? EVENTS.PAYMENT_APPROVED : EVENTS.PAYMENT_REJECTED, {
      orderId: order._id,
      orderNumber: order.orderNumber,
      customerId: order.customer,
      method: PAYMENT_METHODS.MANUAL_RECEIPT,
      reason: note,
    });
  }

  return payment;
}

module.exports = {
  createStripeCheckoutSession,
  handleStripeWebhook,
  attachReceiptUpload,
  reviewReceiptPayment,
};
