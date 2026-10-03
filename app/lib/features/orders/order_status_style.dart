import '../../core/roles.dart';
import '../../core/theme/status_style.dart';

String orderStatusLabel(String status) {
  switch (status) {
    case OrderStatus.pending:
      return 'Pending';
    case OrderStatus.paymentSubmitted:
      return 'Payment submitted';
    case OrderStatus.paymentUnderReview:
      return 'Payment under review';
    case OrderStatus.paymentApproved:
      return 'Payment approved';
    case OrderStatus.paymentRejected:
      return 'Payment rejected';
    case OrderStatus.confirmed:
      return 'Order confirmed';
    case OrderStatus.processing:
      return 'Processing';
    case OrderStatus.packing:
      return 'Packing';
    case OrderStatus.dispatched:
      return 'Dispatched';
    case OrderStatus.outForDelivery:
      return 'Out for delivery';
    case OrderStatus.delivered:
      return 'Delivered';
    case OrderStatus.completed:
      return 'Completed';
    case OrderStatus.cancelled:
      return 'Cancelled';
    default:
      return status.replaceAll('_', ' ');
  }
}

/// Short customer-facing explanation shown under the status on tracking.
String orderStatusHint(String status) {
  switch (status) {
    case OrderStatus.pending:
      return 'We have received your order.';
    case OrderStatus.paymentSubmitted:
      return 'Your payment proof has been submitted.';
    case OrderStatus.paymentUnderReview:
      return 'An admin is verifying your receipt. Nothing else is needed from you right now.';
    case OrderStatus.paymentApproved:
      return 'Your payment has been verified.';
    case OrderStatus.paymentRejected:
      return 'Your receipt was not accepted. Please upload the correct payment proof.';
    case OrderStatus.confirmed:
      return 'Your order is confirmed and queued for preparation.';
    case OrderStatus.processing:
      return 'We are preparing your items.';
    case OrderStatus.packing:
      return 'Your items are being packed.';
    case OrderStatus.dispatched:
      return 'Your parcel has left the shop.';
    case OrderStatus.outForDelivery:
      return 'The courier is on the way.';
    case OrderStatus.delivered:
      return 'Your order has been delivered.';
    case OrderStatus.completed:
      return 'Order complete. Thank you!';
    case OrderStatus.cancelled:
      return 'This order was cancelled.';
    default:
      return '';
  }
}

StatusTone orderStatusTone(String status) {
  switch (status) {
    case OrderStatus.delivered:
    case OrderStatus.completed:
    case OrderStatus.confirmed:
    case OrderStatus.paymentApproved:
      return StatusTone.success;
    case OrderStatus.processing:
    case OrderStatus.packing:
    case OrderStatus.dispatched:
    case OrderStatus.outForDelivery:
      return StatusTone.info;
    case OrderStatus.paymentSubmitted:
    case OrderStatus.paymentUnderReview:
      return StatusTone.warning;
    case OrderStatus.cancelled:
    case OrderStatus.paymentRejected:
      return StatusTone.danger;
    default:
      return StatusTone.neutral;
  }
}

String paymentStatusLabel(String status) {
  switch (status) {
    case PaymentStatus.unpaid:
      return 'Unpaid';
    case PaymentStatus.pendingReview:
      return 'Payment under review';
    case PaymentStatus.approved:
      return 'Payment approved';
    case PaymentStatus.paid:
      return 'Paid';
    case PaymentStatus.rejected:
      return 'Payment rejected';
    case PaymentStatus.failed:
      return 'Payment failed';
    default:
      return status;
  }
}

StatusTone paymentStatusTone(String status) {
  switch (status) {
    case PaymentStatus.paid:
    case PaymentStatus.approved:
      return StatusTone.success;
    case PaymentStatus.pendingReview:
      return StatusTone.warning;
    case PaymentStatus.rejected:
    case PaymentStatus.failed:
      return StatusTone.danger;
    default:
      return StatusTone.neutral;
  }
}

String paymentMethodLabel(String method) {
  switch (method) {
    case PaymentMethod.stripe:
      return 'Card (Stripe)';
    case PaymentMethod.manualReceipt:
      return 'Bank transfer / receipt upload';
    case PaymentMethod.cashOnDelivery:
      return 'Cash on delivery';
    default:
      return method;
  }
}
