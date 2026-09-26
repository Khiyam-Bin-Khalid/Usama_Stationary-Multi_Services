/// Mirrors backend/src/utils/constants.js — keep in sync.
class UserRole {
  static const superadmin = 'superadmin';
  static const admin = 'admin';
  static const staff = 'staff';
  static const customer = 'customer';

  static bool isPosAdminShell(String role) => role != customer;
}

class ProductCategory {
  static const printing = 'printing';
  static const stationery = 'stationery';
  static const grocery = 'grocery';
  static const garment = 'garment';
  static const sports = 'sports';

  static const all = [printing, stationery, grocery, garment, sports];

  static String label(String value) {
    switch (value) {
      case printing:
        return 'Printing';
      case stationery:
        return 'Stationery';
      case grocery:
        return 'Grocery';
      case garment:
        return 'Garment Printing';
      case sports:
        return 'Sports';
      default:
        return value;
    }
  }
}

class OrderStatus {
  static const pending = 'pending';
  static const confirmed = 'confirmed';
  static const processing = 'processing';
  static const outForDelivery = 'out_for_delivery';
  static const delivered = 'delivered';
  static const cancelled = 'cancelled';
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
