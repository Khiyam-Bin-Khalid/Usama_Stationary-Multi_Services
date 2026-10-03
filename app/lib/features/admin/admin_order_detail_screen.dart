import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../core/format.dart';
import '../../core/providers.dart';
import '../../core/responsive.dart';
import '../../core/roles.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/status_style.dart';
import '../../data/models/order.dart';
import '../../widgets/order_widgets.dart';
import '../../widgets/product_image.dart';
import '../orders/order_status_style.dart';
import 'orders_admin_screen.dart';
import 'payment_review_screen.dart';

final adminOrderDetailProvider = FutureProvider.autoDispose.family<CustomerOrder, String>((ref, id) => ref.watch(orderApiProvider).getOrder(id));

/// Admin view of one order: customer + delivery info, every ordered product
/// with its image/SKU/qty/price, totals, the payment record with the
/// uploaded receipt (approve / reject), the status history, and the next
/// fulfilment action.
class AdminOrderDetailScreen extends ConsumerStatefulWidget {
  final String orderId;
  const AdminOrderDetailScreen({super.key, required this.orderId});

  @override
  ConsumerState<AdminOrderDetailScreen> createState() => _AdminOrderDetailScreenState();
}

class _AdminOrderDetailScreenState extends ConsumerState<AdminOrderDetailScreen> {
  bool _busy = false;

  void _refreshAll() {
    ref.invalidate(adminOrderDetailProvider(widget.orderId));
    ref.invalidate(adminOrdersProvider);
    ref.invalidate(orderStatusCountsProvider);
    ref.invalidate(pendingPaymentsProvider);
    ref.invalidate(unreadNotificationsProvider);
  }

  void _toast(String message, {bool error = false}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message), backgroundColor: error ? AppColors.accentRed : AppColors.success));
  }

  Future<void> _setStatus(String status) async {
    final noteController = TextEditingController();
    final courierController = TextEditingController();
    final trackingController = TextEditingController();
    final isDispatch = status == OrderStatus.dispatched || status == OrderStatus.outForDelivery;
    final isCancel = status == OrderStatus.cancelled;
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(isCancel ? 'Cancel this order?' : 'Mark as ${orderStatusLabel(status)}'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (isCancel) const Text('Reserved stock will be returned to inventory and the customer will be notified.'),
            if (isDispatch) ...[
              TextField(controller: courierController, decoration: const InputDecoration(labelText: 'Courier / rider name (optional)')),
              const SizedBox(height: 8),
              TextField(controller: trackingController, decoration: const InputDecoration(labelText: 'Tracking number / note (optional)')),
              const SizedBox(height: 8),
            ],
            TextField(controller: noteController, decoration: InputDecoration(labelText: isCancel ? 'Reason' : 'Note (optional)')),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Back')),
          FilledButton(
            style: isCancel ? FilledButton.styleFrom(backgroundColor: AppColors.accentRed) : null,
            onPressed: () => Navigator.pop(ctx, true),
            child: Text(isCancel ? 'Cancel order' : 'Confirm'),
          ),
        ],
      ),
    );
    if (ok != true) return;
    setState(() => _busy = true);
    try {
      await ref.read(orderApiProvider).updateStatus(
            widget.orderId,
            status: status,
            note: noteController.text.trim(),
            courierName: courierController.text.trim(),
            trackingNote: trackingController.text.trim(),
          );
      _refreshAll();
      _toast('Order marked as ${orderStatusLabel(status)}');
    } catch (e) {
      _toast(e.toString(), error: true);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _review(OrderPayment payment, {required bool approve}) async {
    final note = await showReviewDialog(context, approve: approve);
    if (note == null) return;
    setState(() => _busy = true);
    try {
      await ref.read(paymentApiProvider).review(payment.id, approve: approve, note: note);
      _refreshAll();
      _toast(approve ? 'Payment approved — order confirmed' : 'Payment rejected — customer notified');
    } catch (e) {
      _toast(e.toString(), error: true);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final role = ref.watch(authStateProvider).valueOrNull?.role ?? UserRole.staff;
    final canManage = Permissions.manageOrders(role);
    final canReview = Permissions.reviewPayments(role);
    final orderAsync = ref.watch(adminOrderDetailProvider(widget.orderId));

    return orderAsync.when(
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (e, _) => Center(child: Text('Could not load order: $e')),
      data: (order) {
        final payment = order.payment;
        final next = OrderStatus.nextStep(order.status);
        final paymentSettled = order.paymentMethod == PaymentMethod.cashOnDelivery ||
            order.paymentStatus == PaymentStatus.approved ||
            order.paymentStatus == PaymentStatus.paid;
        final canConfirm = (order.status == OrderStatus.pending || order.status == OrderStatus.paymentApproved) && paymentSettled;

        final items = Card(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Ordered products (${order.itemCount})', style: Theme.of(context).textTheme.titleMedium),
                for (final item in order.items) OrderItemTile(item: item, imageSize: 64),
                const Divider(),
                OrderTotals(subtotal: order.subtotal, discountTotal: order.discountTotal, deliveryFee: order.deliveryFee, taxAmount: order.taxAmount, total: order.total),
              ],
            ),
          ),
        );

        final customerCard = Card(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Customer & delivery', style: Theme.of(context).textTheme.titleMedium),
                const SizedBox(height: 8),
                Text(order.customer?.name ?? 'Customer', style: const TextStyle(fontWeight: FontWeight.w600)),
                if (order.customer?.email != null) Text(order.customer!.email!, style: Theme.of(context).textTheme.bodySmall),
                if (order.customer?.phone != null) Text(order.customer!.phone!, style: Theme.of(context).textTheme.bodySmall),
                const SizedBox(height: 8),
                Text(order.addressLine.isEmpty ? 'Pickup from store' : order.addressLine),
                if (order.address?['phone'] != null) Text('Delivery phone: ${order.address!['phone']}', style: Theme.of(context).textTheme.bodySmall),
                if (order.deliveryWindow != null && order.deliveryWindow!.isNotEmpty) Text('Preferred time: ${order.deliveryWindow}', style: Theme.of(context).textTheme.bodySmall),
                if (order.courierName != null && order.courierName!.isNotEmpty) Text('Courier: ${order.courierName}', style: Theme.of(context).textTheme.bodySmall),
                if (order.trackingNote != null && order.trackingNote!.isNotEmpty) Text('Tracking: ${order.trackingNote}', style: Theme.of(context).textTheme.bodySmall),
              ],
            ),
          ),
        );

        final paymentCard = Card(
          color: payment != null && payment.status == PaymentStatus.pendingReview ? AppColors.tint(AppColors.primaryOrange) : null,
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(child: Text('Payment', style: Theme.of(context).textTheme.titleMedium)),
                    StatusBadge(label: paymentStatusLabel(order.paymentStatus), tone: paymentStatusTone(order.paymentStatus)),
                  ],
                ),
                const SizedBox(height: 6),
                Text('${paymentMethodLabel(order.paymentMethod)} · ${formatCurrency(payment?.amount ?? order.total)}', style: Theme.of(context).textTheme.bodySmall),
                if (payment != null && payment.hasReceipt) ...[
                  const SizedBox(height: 12),
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      GestureDetector(
                        onTap: () => showImageViewer(context, payment.receiptImageUrl!, title: 'Receipt · ${order.orderNumber}'),
                        child: ProductImage(imageUrl: payment.receiptImageUrl, size: 120),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Text('Uploaded receipt', style: TextStyle(fontWeight: FontWeight.w600)),
                            if (payment.receiptUploadedAt != null) Text(formatDateTime(payment.receiptUploadedAt!), style: Theme.of(context).textTheme.bodySmall),
                            if (payment.receiptNote != null && payment.receiptNote!.isNotEmpty) Text('Customer note: ${payment.receiptNote}'),
                            if (payment.reviewedAt != null)
                              Text('Reviewed by ${payment.reviewedByName ?? 'admin'} · ${formatDateTime(payment.reviewedAt!)}${payment.reviewNote != null && payment.reviewNote!.isNotEmpty ? '\n${payment.reviewNote}' : ''}',
                                  style: Theme.of(context).textTheme.bodySmall),
                            TextButton.icon(
                              onPressed: () => showImageViewer(context, payment.receiptImageUrl!, title: 'Receipt · ${order.orderNumber}'),
                              icon: const Icon(Icons.zoom_in, size: 18),
                              label: const Text('View receipt'),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ] else if (order.paymentMethod == PaymentMethod.manualReceipt) ...[
                  const SizedBox(height: 8),
                  const Text('The customer has not uploaded a receipt yet.'),
                ],
                if (canReview && payment != null && payment.status == PaymentStatus.pendingReview && payment.hasReceipt) ...[
                  const SizedBox(height: 12),
                  const Text('Verify the receipt against the order total, then decide:', style: TextStyle(fontWeight: FontWeight.w600)),
                  const SizedBox(height: 8),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      FilledButton.icon(
                        onPressed: _busy ? null : () => _review(payment, approve: true),
                        icon: const Icon(Icons.check, size: 18),
                        label: const Text('Approve payment'),
                      ),
                      OutlinedButton.icon(
                        onPressed: _busy ? null : () => _review(payment, approve: false),
                        style: OutlinedButton.styleFrom(foregroundColor: AppColors.accentRed, side: const BorderSide(color: AppColors.accentRed)),
                        icon: const Icon(Icons.close, size: 18),
                        label: const Text('Reject'),
                      ),
                    ],
                  ),
                ],
              ],
            ),
          ),
        );

        final actions = Card(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Fulfilment', style: Theme.of(context).textTheme.titleMedium),
                const SizedBox(height: 4),
                Text(
                  OrderStatus.isTerminal(order.status)
                      ? 'This order is ${orderStatusLabel(order.status).toLowerCase()}.'
                      : (!paymentSettled
                          ? 'Waiting for payment approval before processing can start.'
                          : 'Advance the order as it moves through the shop.'),
                  style: Theme.of(context).textTheme.bodySmall,
                ),
                const SizedBox(height: 12),
                if (canManage && !OrderStatus.isTerminal(order.status))
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      if (canConfirm)
                        FilledButton.icon(onPressed: _busy ? null : () => _setStatus(OrderStatus.confirmed), icon: const Icon(Icons.verified_outlined, size: 18), label: const Text('Confirm order')),
                      if (next != null && paymentSettled)
                        FilledButton.icon(onPressed: _busy ? null : () => _setStatus(next), icon: const Icon(Icons.arrow_forward, size: 18), label: Text('Mark as ${orderStatusLabel(next)}')),
                      PopupMenuButton<String>(
                        enabled: !_busy,
                        tooltip: 'Other status',
                        onSelected: _setStatus,
                        itemBuilder: (ctx) => [
                          for (final s in OrderStatus.adminSettable)
                            if (s != order.status && s != OrderStatus.cancelled) PopupMenuItem(value: s, child: Text(orderStatusLabel(s))),
                        ],
                        child: const OutlinedButton(onPressed: null, child: Text('Set status…')),
                      ),
                      OutlinedButton.icon(
                        onPressed: _busy ? null : () => _setStatus(OrderStatus.cancelled),
                        style: OutlinedButton.styleFrom(foregroundColor: AppColors.accentRed, side: const BorderSide(color: AppColors.accentRed)),
                        icon: const Icon(Icons.cancel_outlined, size: 18),
                        label: const Text('Cancel order'),
                      ),
                    ],
                  ),
                const SizedBox(height: 16),
                Text('History', style: Theme.of(context).textTheme.titleSmall),
                const SizedBox(height: 8),
                OrderTimeline(order: order),
              ],
            ),
          ),
        );

        final left = Column(children: [paymentCard, const SizedBox(height: 16), items, const SizedBox(height: 16), customerCard]);

        return RefreshIndicator(
          onRefresh: () async => _refreshAll(),
          child: SingleChildScrollView(
            physics: const AlwaysScrollableScrollPhysics(),
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    IconButton(onPressed: () => context.go('/admin/orders'), icon: const Icon(Icons.arrow_back)),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(order.orderNumber, style: Theme.of(context).textTheme.titleLarge),
                          Text('Placed ${formatDateTime(order.createdAt)}', style: Theme.of(context).textTheme.bodySmall),
                        ],
                      ),
                    ),
                    OrderStatusChips(order: order),
                  ],
                ),
                const SizedBox(height: 12),
                if (context.screenWidth >= 1100)
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(flex: 3, child: left),
                      const SizedBox(width: 16),
                      Expanded(flex: 2, child: actions),
                    ],
                  )
                else ...[
                  actions,
                  const SizedBox(height: 16),
                  left,
                ],
              ],
            ),
          ),
        );
      },
    );
  }
}
