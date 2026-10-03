const Notification = require('../models/Notification');
const User = require('../models/User');
const { domainEvents, EVENTS } = require('./events');
const { sendMail } = require('./mailer');
const { NOTIFICATION_TYPES, ROLES } = require('../utils/constants');

const ADMINS = [ROLES.SUPERADMIN, ROLES.ADMIN];

// Spec §5 — trigger → recipients → channel. Adding a new alert type means
// adding one row here plus one `domainEvents.emitSafe(...)` at the source.
const RULES = {
  [EVENTS.LOW_STOCK]: (p) => ({
    type: NOTIFICATION_TYPES.LOW_STOCK,
    recipientRoles: ADMINS,
    channels: ['in_app', 'email'],
    title: `Low stock: ${p.productName}`,
    message: `${p.productName} (${p.category}) is down to ${p.currentStock} ${p.unit || 'units'} (threshold ${p.reorderThreshold}).`,
  }),
  [EVENTS.OUT_OF_STOCK]: (p) => ({
    type: NOTIFICATION_TYPES.OUT_OF_STOCK,
    recipientRoles: ADMINS,
    channels: ['in_app', 'email'],
    title: `Out of stock: ${p.productName}`,
    message: `${p.productName} (${p.category}) has reached 0 and was removed from the sellable list.`,
  }),
  [EVENTS.CUSTOMER_REGISTERED]: (p) => ({
    type: NOTIFICATION_TYPES.CUSTOMER_REGISTERED,
    recipientRoles: ADMINS,
    channels: ['in_app'],
    title: 'New customer registered',
    message: `${p.name} (${p.email}) created an account on the web store.`,
  }),
  [EVENTS.ORDER_PLACED]: (p) => ({
    type: NOTIFICATION_TYPES.ORDER_PLACED,
    recipientRoles: [ROLES.ADMIN, ROLES.STAFF],
    channels: ['in_app'],
    title: `New online order ${p.orderNumber}`,
    message: `${p.customerName || 'A customer'} placed an order for Rs. ${p.total} (${p.itemCount} item(s), ${p.paymentMethod}).`,
  }),
  // Consolidated spec: a receipt was uploaded and needs an explicit admin
  // decision before the order can move on.
  [EVENTS.PAYMENT_REVIEW_REQUIRED]: (p) => ({
    type: NOTIFICATION_TYPES.PAYMENT_REVIEW_REQUIRED,
    recipientRoles: ADMINS,
    channels: ['in_app', 'email'],
    title: `${p.isResubmission ? 'Corrected receipt' : 'Receipt'} to review: ${p.orderNumber}`,
    message: `A payment receipt for order ${p.orderNumber} (Rs. ${p.amount}) is waiting for verification. Approve or reject it from Payment review.`,
  }),
  // Customer-facing: receipt rejected → fix and re-upload.
  [EVENTS.PAYMENT_REJECTED]: (p) => ({
    type: NOTIFICATION_TYPES.PAYMENT_REJECTED,
    recipientUser: p.customerId,
    channels: ['in_app', 'email'],
    title: `Payment receipt rejected for ${p.orderNumber}`,
    message: `Your receipt for order ${p.orderNumber} was not accepted${p.reason ? `: ${p.reason}` : ''}. Please upload the correct payment proof from the order page.`,
  }),
  [EVENTS.PAYMENT_APPROVED]: (p) => ({
    type: NOTIFICATION_TYPES.PAYMENT_APPROVED,
    recipientUser: p.customerId,
    channels: ['in_app'],
    title: `Payment approved for ${p.orderNumber}`,
    message: `Your payment for order ${p.orderNumber} has been verified. We are now preparing your order.`,
  }),
  [EVENTS.ORDER_STATUS_CHANGED]: (p) => ({
    type: NOTIFICATION_TYPES.ORDER_STATUS_CHANGED,
    recipientUser: p.customerId,
    channels: ['in_app'],
    title: `Order ${p.orderNumber}: ${String(p.status).replace(/_/g, ' ')}`,
    message: `Your order ${p.orderNumber} is now ${String(p.status).replace(/_/g, ' ')}${p.note ? ` — ${p.note}` : ''}.`,
  }),
  [EVENTS.PAYMENT_FAILED]: (p) => ({
    type: NOTIFICATION_TYPES.PAYMENT_FAILED,
    recipientRoles: [ROLES.ADMIN],
    channels: ['in_app', 'email'],
    title: `Payment failed for ${p.orderNumber}`,
    message: `Payment for order ${p.orderNumber} failed${p.reason ? `: ${p.reason}` : ''}.`,
  }),
  [EVENTS.SYNC_FAILED]: (p) => ({
    type: NOTIFICATION_TYPES.SYNC_FAILED,
    recipientRoles: ADMINS,
    channels: ['in_app', 'email'],
    title: 'Desktop POS sync failure',
    message: `${p.failedCount} queued sale(s) from ${p.cashierName || 'a POS terminal'} could not be synced: ${p.firstError}`,
  }),
  [EVENTS.DISCREPANCY_REPORTED]: (p) => ({
    type: NOTIFICATION_TYPES.INVENTORY_DISCREPANCY,
    recipientRoles: ADMINS,
    channels: ['in_app'],
    title: `Stock discrepancy reported: ${p.productName}`,
    message: `${p.reportedByName} counted ${p.countedQty} but the system has ${p.systemQty} (${p.category}).`,
  }),
};

async function deliver(event, payload) {
  const rule = RULES[event];
  if (!rule) return null;
  const spec = rule(payload);

  if (!spec.recipientUser && !(spec.recipientRoles && spec.recipientRoles.length)) return null;
  const notification = await Notification.create({ ...spec, recipientRoles: spec.recipientRoles || [], payload });

  if (spec.channels.includes('email')) {
    const query = spec.recipientUser
      ? { _id: spec.recipientUser, isActive: true, deletedAt: null }
      : { role: { $in: spec.recipientRoles }, isActive: true, deletedAt: null };
    const recipients = await User.find(query, 'email');
    if (recipients.length) {
      await sendMail({ to: recipients.map((u) => u.email), subject: spec.title, text: spec.message });
    }
  }
  return notification;
}

let started = false;
function start() {
  if (started) return;
  started = true;
  for (const event of Object.keys(RULES)) {
    domainEvents.on(event, (payload) => {
      deliver(event, payload).catch((err) => {
        console.error(`[notifications] failed to deliver "${event}":`, err); // eslint-disable-line no-console
      });
    });
  }
}

// ---- Queries used by the API ----

// Role-addressed alerts for staff roles, plus anything addressed to this
// person directly (customers only ever get the latter).
function roleFilter(user) {
  return { $or: [{ recipientRoles: user.role }, { recipientUser: user._id }] };
}

async function listForUser(user, { unreadOnly = false, page = 1, limit = 50 } = {}) {
  const filter = roleFilter(user);
  if (unreadOnly) filter.readBy = { $ne: user._id };
  const total = await Notification.countDocuments(filter);
  const docs = await Notification.find(filter).sort({ createdAt: -1 }).skip((page - 1) * limit).limit(limit).lean();
  const notifications = docs.map((n) => ({
    ...n,
    isRead: (n.readBy || []).some((id) => id.toString() === user._id.toString()),
    readBy: undefined,
  }));
  return { notifications, total, page, limit };
}

function unreadCount(user) {
  return Notification.countDocuments({ ...roleFilter(user), readBy: { $ne: user._id } });
}

async function markRead(user, id) {
  return Notification.findOneAndUpdate({ _id: id, ...roleFilter(user) }, { $addToSet: { readBy: user._id } }, { new: true });
}

async function markAllRead(user) {
  const res = await Notification.updateMany({ ...roleFilter(user), readBy: { $ne: user._id } }, { $addToSet: { readBy: user._id } });
  return res.modifiedCount;
}

module.exports = { start, deliver, listForUser, unreadCount, markRead, markAllRead };
