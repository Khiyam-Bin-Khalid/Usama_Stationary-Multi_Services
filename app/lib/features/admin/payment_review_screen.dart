import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../core/format.dart';
import '../../core/providers.dart';
import '../../core/theme/app_colors.dart';
import '../../data/remote/payment_api.dart';
import '../../widgets/order_widgets.dart';
import '../../widgets/product_image.dart';
import 'orders_admin_screen.dart';

final pendingPaymentsProvider = FutureProvider.autoDispose<List<PendingPayment>>((ref) => ref.watch(paymentApiProvider).pendingReview());

/// Asks for the review note; returns null when the admin backs out.
Future<String?> showReviewDialog(BuildContext context, {required bool approve}) async {
  final controller = TextEditingController();
  final ok = await showDialog<bool>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: Text(approve ? 'Approve payment' : 'Reject payment'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(approve
              ? 'Confirm that the receipt matches the order total. The order will move to Confirmed.'
              : 'The customer will be notified with this reason and asked to upload the correct receipt.'),
          const SizedBox(height: 12),
          TextField(
            controller: controller,
            decoration: InputDecoration(labelText: approve ? 'Note (optional)' : 'Reason (shown to the customer)'),
          ),
        ],
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Back')),
        FilledButton(
          style: approve ? null : FilledButton.styleFrom(backgroundColor: AppColors.accentRed),
          onPressed: () => Navigator.pop(ctx, true),
          child: Text(approve ? 'Approve' : 'Reject'),
        ),
      ],
    ),
  );
  if (ok != true) return null;
  return controller.text.trim();
}

/// Receipts awaiting verification. Each card shows the full order (customer,
/// product images, SKUs, quantities, total) next to the uploaded receipt so
/// the admin can compare them, then explicitly approve or reject.
class PaymentReviewScreen extends ConsumerStatefulWidget {
  const PaymentReviewScreen({super.key});

  @override
  ConsumerState<PaymentReviewScreen> createState() => _PaymentReviewScreenState();
}

class _PaymentReviewScreenState extends ConsumerState<PaymentReviewScreen> {
  String? _busyId;

  Future<void> _decide(PendingPayment entry, {required bool approve}) async {
    final note = await showReviewDialog(context, approve: approve);
    if (note == null) return;
    setState(() => _busyId = entry.payment.id);
    try {
      await ref.read(paymentApiProvider).review(entry.payment.id, approve: approve, note: note);
      ref.invalidate(pendingPaymentsProvider);
      ref.invalidate(adminOrdersProvider);
      ref.invalidate(orderStatusCountsProvider);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(approve ? 'Payment approved — order confirmed' : 'Payment rejected — customer notified'),
        backgroundColor: approve ? AppColors.success : AppColors.accentRed,
      ));
    } catch (e) {
      final message = e.toString();
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));
    } finally {
      if (mounted) setState(() => _busyId = null);
    }
  }

  @override
  Widget build(BuildContext context) {
    final paymentsAsync = ref.watch(pendingPaymentsProvider);

    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
          child: Row(
            children: [
              Text('Payment review', style: Theme.of(context).textTheme.titleLarge),
              const Spacer(),
              IconButton(icon: const Icon(Icons.refresh), onPressed: () => ref.invalidate(pendingPaymentsProvider)),
            ],
          ),
        ),
        Expanded(
          child: paymentsAsync.when(
            loading: () => const Center(child: CircularProgressIndicator()),
            error: (e, _) => Center(child: Text('Failed to load: $e')),
            data: (payments) {
              if (payments.isEmpty) return const Center(child: Text('No receipts awaiting review'));
              return ListView.builder(
                padding: const EdgeInsets.all(16),
                itemCount: payments.length,
                itemBuilder: (context, i) => _ReviewCard(
                  entry: payments[i],
                  busy: _busyId == payments[i].payment.id,
                  onApprove: () => _decide(payments[i], approve: true),
                  onReject: () => _decide(payments[i], approve: false),
                ),
              );
            },
          ),
        ),
      ],
    );
  }
}

class _ReviewCard extends StatelessWidget {
  final PendingPayment entry;
  final bool busy;
  final VoidCallback onApprove;
  final VoidCallback onReject;
  const _ReviewCard({required this.entry, required this.busy, required this.onApprove, required this.onReject});

  @override
  Widget build(BuildContext context) {
    final payment = entry.payment;
    final order = entry.order;
    final wide = MediaQuery.sizeOf(context).width >= 900;

    final receipt = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('Receipt', style: Theme.of(context).textTheme.titleSmall),
        const SizedBox(height: 6),
        GestureDetector(
          onTap: payment.hasReceipt ? () => showImageViewer(context, payment.receiptImageUrl!, title: 'Receipt · ${order?.orderNumber ?? ''}') : null,
          child: ProductImage(imageUrl: payment.receiptImageUrl, width: wide ? 220 : double.infinity, height: 180),
        ),
        if (payment.receiptUploadedAt != null) Text('Uploaded ${formatDateTime(payment.receiptUploadedAt!)}', style: Theme.of(context).textTheme.bodySmall),
        if (payment.receiptNote != null && payment.receiptNote!.isNotEmpty) Text('Note: ${payment.receiptNote}', style: Theme.of(context).textTheme.bodySmall),
        TextButton.icon(
          onPressed: payment.hasReceipt ? () => showImageViewer(context, payment.receiptImageUrl!, title: 'Receipt · ${order?.orderNumber ?? ''}') : null,
          icon: const Icon(Icons.zoom_in, size: 18),
          label: const Text('View full size'),
        ),
      ],
    );

    final details = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(child: Text('Order ${order?.orderNumber ?? ''}', style: Theme.of(context).textTheme.titleMedium)),
            Text(formatCurrency(payment.amount), style: Theme.of(context).textTheme.titleMedium?.copyWith(color: AppColors.primaryDark)),
          ],
        ),
        Text(
          '${order?.customer?.name ?? 'Customer'}${order?.customer?.phone != null ? ' · ${order!.customer!.phone}' : ''}${order != null ? ' · placed ${formatDateTime(order.createdAt)}' : ''}',
          style: Theme.of(context).textTheme.bodySmall,
        ),
        if (order != null) ...[
          const SizedBox(height: 8),
          for (final item in order.items) OrderItemTile(item: item, imageSize: 44, dense: true),
          const Divider(),
          OrderTotals(subtotal: order.subtotal, discountTotal: order.discountTotal, deliveryFee: order.deliveryFee, taxAmount: order.taxAmount, total: order.total),
        ],
        const SizedBox(height: 12),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            FilledButton.icon(onPressed: busy ? null : onApprove, icon: const Icon(Icons.check, size: 18), label: const Text('Approve')),
            OutlinedButton.icon(
              onPressed: busy ? null : onReject,
              style: OutlinedButton.styleFrom(foregroundColor: AppColors.accentRed, side: const BorderSide(color: AppColors.accentRed)),
              icon: const Icon(Icons.close, size: 18),
              label: const Text('Reject'),
            ),
            if (order != null) TextButton(onPressed: () => context.go('/admin/orders/${order.id}'), child: const Text('Open order')),
          ],
        ),
      ],
    );

    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: wide
            ? Row(crossAxisAlignment: CrossAxisAlignment.start, children: [receipt, const SizedBox(width: 20), Expanded(child: details)])
            : Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [receipt, const SizedBox(height: 12), details]),
      ),
    );
  }
}
