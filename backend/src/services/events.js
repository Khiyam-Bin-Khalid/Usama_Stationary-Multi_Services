const { EventEmitter } = require('events');

// Spec §5 / §9: business actions (sale completed, stock updated, user
// registered, ...) emit domain events here; the Notification Service
// subscribes and decides who gets told and how. Inventory/sales/order code
// never needs to know about recipients.
//
// Handlers run asynchronously and must never throw into the emitter — a
// failed notification should not fail the sale that triggered it.
class DomainEvents extends EventEmitter {
  emitSafe(event, payload) {
    // Defer so the emitting request finishes its own DB writes first.
    setImmediate(() => {
      try {
        this.emit(event, payload);
      } catch (err) {
        console.error(`[events] handler for "${event}" threw:`, err); // eslint-disable-line no-console
      }
    });
  }
}

const domainEvents = new DomainEvents();
domainEvents.setMaxListeners(50);

const EVENTS = Object.freeze({
  LOW_STOCK: 'inventory.low_stock',
  OUT_OF_STOCK: 'inventory.out_of_stock',
  DISCREPANCY_REPORTED: 'inventory.discrepancy_reported',
  CUSTOMER_REGISTERED: 'user.customer_registered',
  ORDER_PLACED: 'order.placed',
  PAYMENT_FAILED: 'payment.failed',
  PAYMENT_REVIEW_REQUIRED: 'payment.review_required',
  PAYMENT_REJECTED: 'payment.rejected',
  PAYMENT_APPROVED: 'payment.approved',
  ORDER_STATUS_CHANGED: 'order.status_changed',
  SYNC_FAILED: 'sync.failed',
});

module.exports = { domainEvents, EVENTS };
