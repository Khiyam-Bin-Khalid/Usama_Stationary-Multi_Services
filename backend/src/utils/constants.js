const ROLES = Object.freeze({
  SUPERADMIN: 'superadmin',
  ADMIN: 'admin',
  STAFF: 'staff',
  CUSTOMER: 'customer',
});

const PRODUCT_CATEGORIES = Object.freeze({
  PRINTING: 'printing',
  STATIONERY: 'stationery',
  GROCERY: 'grocery',
  GARMENT: 'garment',
  SPORTS: 'sports',
});

const INVENTORY_LOG_TYPES = Object.freeze({
  PURCHASE: 'purchase',
  SALE: 'sale',
  ADJUSTMENT: 'adjustment',
  RETURN: 'return',
});

const JOB_STATUSES = Object.freeze({
  NONE: 'none',
  QUEUED: 'queued',
  IN_PROGRESS: 'in_progress',
  READY: 'ready',
});

// Full order lifecycle (consolidated spec): payment stages are driven by the
// payment flow (receipt upload / admin review / Stripe webhook); the
// fulfilment stages are advanced by Admin from the order-management screen.
const ORDER_STATUSES = Object.freeze({
  PENDING: 'pending',
  PAYMENT_SUBMITTED: 'payment_submitted',
  PAYMENT_UNDER_REVIEW: 'payment_under_review',
  PAYMENT_APPROVED: 'payment_approved',
  PAYMENT_REJECTED: 'payment_rejected',
  CONFIRMED: 'confirmed',
  PROCESSING: 'processing',
  PACKING: 'packing',
  DISPATCHED: 'dispatched',
  OUT_FOR_DELIVERY: 'out_for_delivery',
  DELIVERED: 'delivered',
  COMPLETED: 'completed',
  CANCELLED: 'cancelled',
});

// Statuses an Admin may set by hand (PATCH /orders/:id/status). The payment_*
// statuses are reserved for the payment flow so an order can never be marked
// "payment approved" without a reviewed receipt or a Stripe confirmation.
const ADMIN_SETTABLE_ORDER_STATUSES = Object.freeze([
  ORDER_STATUSES.CONFIRMED,
  ORDER_STATUSES.PROCESSING,
  ORDER_STATUSES.PACKING,
  ORDER_STATUSES.DISPATCHED,
  ORDER_STATUSES.OUT_FOR_DELIVERY,
  ORDER_STATUSES.DELIVERED,
  ORDER_STATUSES.COMPLETED,
  ORDER_STATUSES.CANCELLED,
]);

// Terminal statuses: no further transitions allowed.
const TERMINAL_ORDER_STATUSES = Object.freeze([ORDER_STATUSES.COMPLETED, ORDER_STATUSES.CANCELLED]);

// Auto-generated SKU prefixes per category key (e.g. STN-00001). Categories
// added later fall back to the first three letters of their key.
const SKU_PREFIXES = Object.freeze({
  [PRODUCT_CATEGORIES.STATIONERY]: 'STN',
  [PRODUCT_CATEGORIES.GROCERY]: 'GRO',
  [PRODUCT_CATEGORIES.GARMENT]: 'GAR',
  [PRODUCT_CATEGORIES.PRINTING]: 'PRT',
  [PRODUCT_CATEGORIES.SPORTS]: 'SPT',
});

const PAYMENT_METHODS = Object.freeze({
  STRIPE: 'stripe',
  MANUAL_RECEIPT: 'manual_receipt',
  CASH_ON_DELIVERY: 'cash_on_delivery',
});

const PAYMENT_STATUSES = Object.freeze({
  UNPAID: 'unpaid',
  PENDING_REVIEW: 'pending_review',
  APPROVED: 'approved',
  REJECTED: 'rejected',
  PAID: 'paid',
  FAILED: 'failed',
});

// Spec §4.1 / §5: low-stock threshold defaults to 5 units, configurable per
// category (Category.defaultReorderThreshold) or per product.
const DEFAULT_LOW_STOCK_THRESHOLD = 5;

// Spec §4: categories → products → stock records. Seeded into the
// `categories` collection by categoryService.ensureDefaultCategories().
const DEFAULT_CATEGORIES = Object.freeze([
  { key: PRODUCT_CATEGORIES.STATIONERY, name: 'Stationery', unitType: 'piece', defaultReorderThreshold: 5 },
  { key: PRODUCT_CATEGORIES.GROCERY, name: 'Grocery', unitType: 'kg', defaultReorderThreshold: 5 },
  { key: PRODUCT_CATEGORIES.GARMENT, name: 'Garment Printing', unitType: 'job-order', defaultReorderThreshold: 0 },
  { key: PRODUCT_CATEGORIES.PRINTING, name: 'Printing Services', unitType: 'job-order', defaultReorderThreshold: 0 },
  { key: PRODUCT_CATEGORIES.SPORTS, name: 'Sporting Goods', unitType: 'piece', defaultReorderThreshold: 5 },
]);

// Spec §5: every trigger-based alert the Notification Service knows about.
const NOTIFICATION_TYPES = Object.freeze({
  LOW_STOCK: 'low_stock',
  OUT_OF_STOCK: 'out_of_stock',
  CUSTOMER_REGISTERED: 'customer_registered',
  ORDER_PLACED: 'order_placed',
  PAYMENT_FAILED: 'payment_failed',
  PAYMENT_REVIEW_REQUIRED: 'payment_review_required',
  PAYMENT_REJECTED: 'payment_rejected',
  PAYMENT_APPROVED: 'payment_approved',
  ORDER_STATUS_CHANGED: 'order_status_changed',
  SYNC_FAILED: 'sync_failed',
  INVENTORY_DISCREPANCY: 'inventory_discrepancy',
});

const SHIFT_STATUSES = Object.freeze({
  OPEN: 'open',
  CLOSED: 'closed',
});

const DISCREPANCY_STATUSES = Object.freeze({
  OPEN: 'open',
  RESOLVED: 'resolved',
  DISMISSED: 'dismissed',
});

const DELIVERY_STATUSES = Object.freeze({
  PENDING: 'pending',
  ASSIGNED: 'assigned',
  OUT_FOR_DELIVERY: 'out_for_delivery',
  DELIVERED: 'delivered',
  FAILED: 'failed',
});

module.exports = {
  ROLES,
  PRODUCT_CATEGORIES,
  INVENTORY_LOG_TYPES,
  JOB_STATUSES,
  ORDER_STATUSES,
  ADMIN_SETTABLE_ORDER_STATUSES,
  TERMINAL_ORDER_STATUSES,
  SKU_PREFIXES,
  PAYMENT_METHODS,
  PAYMENT_STATUSES,
  DELIVERY_STATUSES,
  DEFAULT_LOW_STOCK_THRESHOLD,
  DEFAULT_CATEGORIES,
  NOTIFICATION_TYPES,
  SHIFT_STATUSES,
  DISCREPANCY_STATUSES,
};
