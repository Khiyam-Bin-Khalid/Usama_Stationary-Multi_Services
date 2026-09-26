import '../../core/roles.dart';
import '../../core/theme/status_style.dart';

String orderStatusLabel(String status) {
  switch (status) {
    case OrderStatus.pending:
      return 'Pending';
    case OrderStatus.confirmed:
      return 'Confirmed';
    case OrderStatus.processing:
      return 'Processing';
    case OrderStatus.outForDelivery:
      return 'Out for delivery';
    case OrderStatus.delivered:
      return 'Delivered';
    case OrderStatus.cancelled:
      return 'Cancelled';
    default:
      return status;
  }
}

StatusTone orderStatusTone(String status) {
  switch (status) {
    case OrderStatus.delivered:
    case OrderStatus.confirmed:
      return StatusTone.success;
    case OrderStatus.outForDelivery:
    case OrderStatus.processing:
      return StatusTone.info;
    case OrderStatus.cancelled:
      return StatusTone.danger;
    default:
      return StatusTone.neutral;
  }
}

String paymentStatusLabel(String status) {
  switch (status) {
    case 'unpaid':
      return 'Unpaid';
    case 'pending_review':
      return 'Payment under review';
    case 'paid':
      return 'Paid';
    case 'rejected':
      return 'Payment rejected';
    case 'failed':
      return 'Payment failed';
    default:
      return status;
  }
}

StatusTone paymentStatusTone(String status) {
  switch (status) {
    case 'paid':
      return StatusTone.success;
    case 'pending_review':
      return StatusTone.warning;
    case 'rejected':
    case 'failed':
      return StatusTone.danger;
    default:
      return StatusTone.neutral;
  }
}
