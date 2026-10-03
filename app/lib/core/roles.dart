/// Mirrors backend/src/utils/constants.js — keep in sync.
class UserRole {
  static const superadmin = 'superadmin';
  static const admin = 'admin';
  static const staff = 'staff';
  static const customer = 'customer';

  /// Roles that use the Desktop POS / Admin shell (spec §1).
  static const staffRoles = [superadmin, admin, staff];

  static bool isPosAdminShell(String role) => role != customer;

  static String label(String role) {
    switch (role) {
      case superadmin:
        return 'Super Admin';
      case admin:
        return 'Admin';
      case staff:
        return 'Staff';
      case customer:
        return 'Customer';
      default:
        return role;
    }
  }
}

/// Client-side mirror of the spec §2 permission matrix. The server enforces
/// every rule independently; this only decides what to *show*.
class Permissions {
  Permissions._();

  static bool _adminUp(String r) => r == UserRole.superadmin || r == UserRole.admin;

  static bool manageAccounts(String r) => r == UserRole.superadmin;
  static bool viewAuditLog(String r) => r == UserRole.superadmin;
  static bool editInventory(String r) => _adminUp(r);
  static bool consolidatedReports(String r) => _adminUp(r);
  static bool managePromotions(String r) => _adminUp(r);
  static bool manageOrders(String r) => _adminUp(r);
  static bool reviewPayments(String r) => _adminUp(r);
  static bool resolveDiscrepancies(String r) => _adminUp(r);
  static bool receiveStockAlerts(String r) => _adminUp(r);
  static bool recordSales(String r) => UserRole.staffRoles.contains(r);
  static bool reportDiscrepancies(String r) => UserRole.staffRoles.contains(r);
  static bool viewStockMovements(String r) => UserRole.staffRoles.contains(r);
  static bool manageDelivery(String r) => _adminUp(r);

  /// Route-level guard used by the router redirect.
  static bool canAccessPath(String role, String path) {
    if (path.startsWith('/admin/staff')) return manageAccounts(role);
    if (path.startsWith('/admin/audit-log')) return viewAuditLog(role);
    if (path.startsWith('/admin/orders')) return manageOrders(role);
    if (path.startsWith('/admin/delivery')) return manageDelivery(role);
    if (path.startsWith('/admin/payments')) return reviewPayments(role);
    if (path.startsWith('/admin/promotions')) return managePromotions(role);
    return UserRole.staffRoles.contains(role);
  }
}

class ProductCategory {
  static const printing = 'printing';
  static const stationery = 'stationery';
  static const grocery = 'grocery';
  static const garment = 'garment';
  static const sports = 'sports';

  static const all = [stationery, grocery, garment, printing, sports];

  static String label(String value) {
    switch (value) {
      case printing:
        return 'Printing Services';
      case stationery:
        return 'Stationery';
      case grocery:
        return 'Grocery';
      case garment:
        return 'Garment Printing';
      case sports:
        return 'Sporting Goods';
      default:
        return value.isEmpty ? value : value[0].toUpperCase() + value.substring(1).replaceAll('_', ' ');
    }
  }
}

class NotificationType {
  static const lowStock = 'low_stock';
  static const outOfStock = 'out_of_stock';
  static const customerRegistered = 'customer_registered';
  static const orderPlaced = 'order_placed';
  static const paymentFailed = 'payment_failed';
  static const paymentReviewRequired = 'payment_review_required';
  static const paymentRejected = 'payment_rejected';
  static const paymentApproved = 'payment_approved';
  static const orderStatusChanged = 'order_status_changed';
  static const syncFailed = 'sync_failed';
  static const inventoryDiscrepancy = 'inventory_discrepancy';
}

/// Full order lifecycle (mirrors backend ORDER_STATUSES). The payment_*
/// stages are set by the payment flow (receipt upload / admin review /
/// Stripe); the fulfilment stages are advanced by an Admin.
class OrderStatus {
  static const pending = 'pending';
  static const paymentSubmitted = 'payment_submitted';
  static const paymentUnderReview = 'payment_under_review';
  static const paymentApproved = 'payment_approved';
  static const paymentRejected = 'payment_rejected';
  static const confirmed = 'confirmed';
  static const processing = 'processing';
  static const packing = 'packing';
  static const dispatched = 'dispatched';
  static const outForDelivery = 'out_for_delivery';
  static const delivered = 'delivered';
  static const completed = 'completed';
  static const cancelled = 'cancelled';

  /// Display order of the whole lifecycle (used by the tracking timeline).
  static const lifecycle = [
    pending,
    paymentSubmitted,
    paymentUnderReview,
    paymentApproved,
    confirmed,
    processing,
    packing,
    dispatched,
    outForDelivery,
    delivered,
    completed,
  ];

  /// Statuses an Admin may set by hand (backend ADMIN_SETTABLE_ORDER_STATUSES).
  static const adminSettable = [confirmed, processing, packing, dispatched, outForDelivery, delivered, completed, cancelled];

  /// The natural next fulfilment step after [current], or null when none.
  static String? nextStep(String current) {
    switch (current) {
      case confirmed:
        return processing;
      case processing:
        return packing;
      case packing:
        return dispatched;
      case dispatched:
        return outForDelivery;
      case outForDelivery:
        return delivered;
      case delivered:
        return completed;
      default:
        return null;
    }
  }

  static bool isTerminal(String s) => s == completed || s == cancelled;
  static bool isPaymentStage(String s) =>
      s == pending || s == paymentSubmitted || s == paymentUnderReview || s == paymentApproved || s == paymentRejected;
}

/// Admin order-management queues (spec: new, payment review, confirmed,
/// processing, packing, dispatched, delivered, completed, cancelled/rejected).
class OrderQueue {
  final String key;
  final String label;
  final List<String> statuses;
  const OrderQueue(this.key, this.label, this.statuses);

  static const all = [
    OrderQueue('new', 'New', [OrderStatus.pending, OrderStatus.paymentSubmitted]),
    OrderQueue('review', 'Payment review', [OrderStatus.paymentUnderReview]),
    OrderQueue('confirmed', 'Confirmed', [OrderStatus.paymentApproved, OrderStatus.confirmed]),
    OrderQueue('processing', 'Processing', [OrderStatus.processing]),
    OrderQueue('packing', 'Packing', [OrderStatus.packing]),
    OrderQueue('dispatched', 'Dispatched', [OrderStatus.dispatched, OrderStatus.outForDelivery]),
    OrderQueue('delivered', 'Delivered', [OrderStatus.delivered]),
    OrderQueue('completed', 'Completed', [OrderStatus.completed]),
    OrderQueue('cancelled', 'Cancelled / rejected', [OrderStatus.cancelled, OrderStatus.paymentRejected]),
  ];
}

class PaymentMethod {
  static const stripe = 'stripe';
  static const manualReceipt = 'manual_receipt';
  static const cashOnDelivery = 'cash_on_delivery';
}

class PaymentStatus {
  static const unpaid = 'unpaid';
  static const pendingReview = 'pending_review';
  static const approved = 'approved';
  static const rejected = 'rejected';
  static const paid = 'paid';
  static const failed = 'failed';
}
