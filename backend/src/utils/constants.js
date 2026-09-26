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

const ORDER_STATUSES = Object.freeze({
  PENDING: 'pending',
  CONFIRMED: 'confirmed',
  PROCESSING: 'processing',
  OUT_FOR_DELIVERY: 'out_for_delivery',
  DELIVERED: 'delivered',
  CANCELLED: 'cancelled',
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
  PAYMENT_METHODS,
  PAYMENT_STATUSES,
  DELIVERY_STATUSES,
};
