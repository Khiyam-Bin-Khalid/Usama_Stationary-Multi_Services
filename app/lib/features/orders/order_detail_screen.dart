import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:image_picker/image_picker.dart';
import '../../core/config.dart';
import '../../core/format.dart';
import '../../core/providers.dart';
import '../../core/responsive.dart';
import '../../core/roles.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/status_style.dart';
import '../../data/models/order.dart';
import '../../widgets/order_widgets.dart';
import '../../widgets/product_image.dart';
import 'order_status_style.dart';

final _orderDetailProvider =
    FutureProvider.autoDispose.family<CustomerOrder, String>((ref, id) => ref.watch(orderApiProvider).myOrder(id));

/// Customer order page: confirmation, payment / receipt upload with its
/// review status, the ordered items (with the images chosen at purchase
/// time), totals, delivery details and the live tracking timeline.
class OrderDetailScreen extends ConsumerStatefulWidget {
  final String orderId;
  const OrderDetailScreen({super.key, required this.orderId});

  @override
  ConsumerState<OrderDetailScreen> createState() => _OrderDetailScreenState();
}

class _OrderDetailScreenState extends ConsumerState<OrderDetailScreen> {
  bool _uploading = false;

  Future<void> _pickAndUploadReceipt() async {
    final picker = ImagePicker();
    final file = await picker.pickImage(source: ImageSource.gallery, imageQuality: 85);
    if (file == null) return;

    setState(() => _uploading = true);
    try {
      final bytes = await file.readAsBytes();
      await ref.read(paymentApiProvider).uploadReceiptBytes(widget.orderId, bytes, file.name);
      ref.invalidate(_orderDetailProvider(widget.orderId));
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Receipt uploaded — it is now under admin review')));
    } catch (e) {
      final message = e.toString();
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));
    } finally {
      if (mounted) setState(() => _uploading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final orderAsync = ref.watch(_orderDetailProvider(widget.orderId));

    return orderAsync.when(
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (e, _) => Center(child: Text('Could not load order: $e')),
      data: (order) {
        final left = Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _PaymentCard(order: order, uploading: _uploading, onUpload: _pickAndUploadReceipt),
            const SizedBox(height: 16),
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Items (${order.itemCount})', style: Theme.of(context).textTheme.titleMedium),
                    const SizedBox(height: 4),
                    for (final item in order.items) OrderItemTile(item: item, imageSize: 64),
                    const Divider(),
                    OrderTotals(
                      subtotal: order.subtotal,
                      discountTotal: order.discountTotal,
                      deliveryFee: order.deliveryFee,
                      taxAmount: order.taxAmount,
                      total: order.total,
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 16),
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Delivery', style: Theme.of(context).textTheme.titleMedium),
                    const SizedBox(height: 8),
                    Text(order.addressLine.isEmpty ? 'Pickup from store' : order.addressLine),
                    if (order.address?['phone'] != null) Text('Phone: ${order.address!['phone']}', style: Theme.of(context).textTheme.bodySmall),
                    if (order.deliveryWindow != null && order.deliveryWindow!.isNotEmpty)
                      Text('Preferred time: ${order.deliveryWindow}', style: Theme.of(context).textTheme.bodySmall),
                    if (order.courierName != null && order.courierName!.isNotEmpty)
                      Text('Courier: ${order.courierName}', style: Theme.of(context).textTheme.bodySmall),
                    if (order.trackingNote != null && order.trackingNote!.isNotEmpty)
                      Text('Tracking: ${order.trackingNote}', style: Theme.of(context).textTheme.bodySmall),
                  ],
                ),
              ),
            ),
          ],
        );

        final right = Card(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Order tracking', style: Theme.of(context).textTheme.titleMedium),
                const SizedBox(height: 4),
                Text(orderStatusHint(order.status), style: Theme.of(context).textTheme.bodySmall),
                const SizedBox(height: 16),
                OrderTimeline(order: order),
              ],
            ),
          ),
        );

        return RefreshIndicator(
          onRefresh: () async => ref.invalidate(_orderDetailProvider(widget.orderId)),
          child: SingleChildScrollView(
            physics: const AlwaysScrollableScrollPhysics(),
            child: ResponsiveContainer(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      IconButton(onPressed: () => context.go('/orders'), icon: const Icon(Icons.arrow_back)),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(order.orderNumber, style: Theme.of(context).textTheme.headlineSmall),
                            Text('Placed ${formatDateTime(order.createdAt)} · ${paymentMethodLabel(order.paymentMethod)}',
                                style: Theme.of(context).textTheme.bodySmall),
                          ],
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  OrderStatusChips(order: order),
                  const SizedBox(height: 16),
                  if (context.isDesktop)
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Expanded(flex: 3, child: left),
                        const SizedBox(width: 24),
                        Expanded(flex: 2, child: right),
                      ],
                    )
                  else ...[
                    right,
                    const SizedBox(height: 16),
                    left,
                  ],
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}

/// Payment state for the customer: what to do next (upload / re-upload),
/// the receipt they uploaded, and its review outcome.
class _PaymentCard extends StatelessWidget {
  final CustomerOrder order;
  final bool uploading;
  final VoidCallback onUpload;
  const _PaymentCard({required this.order, required this.uploading, required this.onUpload});

  @override
  Widget build(BuildContext context) {
    final payment = order.payment;
    final isReceipt = order.paymentMethod == PaymentMethod.manualReceipt;
    final rejected = order.paymentStatus == PaymentStatus.rejected;
    final needsReceipt = isReceipt && (order.paymentStatus == PaymentStatus.unpaid || rejected) && !OrderStatus.isTerminal(order.status);
    final underReview = order.paymentStatus == PaymentStatus.pendingReview;

    return Card(
      color: needsReceipt
          ? AppColors.tint(rejected ? AppColors.accentRed : AppColors.primaryOrange)
          : (underReview ? AppColors.tint(AppColors.primaryOrange) : null),
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
            Text('${paymentMethodLabel(order.paymentMethod)} · ${formatCurrency(order.total)}', style: Theme.of(context).textTheme.bodySmall),
            if (rejected && payment?.reviewNote != null && payment!.reviewNote!.isNotEmpty) ...[
              const SizedBox(height: 8),
              Text('Reason: ${payment.reviewNote}', style: const TextStyle(color: AppColors.accentRed, fontWeight: FontWeight.w600)),
            ],
            if (needsReceipt) ...[
              const SizedBox(height: 10),
              Text(rejected
                  ? 'Please upload the correct payment proof. It will be reviewed again by an admin.'
                  : 'Pay ${formatCurrency(order.total)} by bank transfer / JazzCash / EasyPaisa, then upload a screenshot of the receipt. An admin will verify it before your order is confirmed.'),
              const SizedBox(height: 10),
              FilledButton.icon(
                onPressed: uploading ? null : onUpload,
                icon: const Icon(Icons.upload_outlined, size: 18),
                label: Text(uploading ? 'Uploading…' : (rejected ? 'Upload corrected receipt' : 'Upload receipt')),
              ),
            ],
            if (underReview) ...[
              const SizedBox(height: 10),
              const Text('Your receipt has been uploaded and is waiting for admin verification. You will be notified once it is approved.'),
            ],
            if (payment != null && payment.hasReceipt) ...[
              const SizedBox(height: 12),
              Row(
                children: [
                  GestureDetector(
                    onTap: () => showImageViewer(context, payment.receiptImageUrl!, title: 'Your receipt'),
                    child: ProductImage(imageUrl: payment.receiptImageUrl, size: 72),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text('Uploaded receipt', style: TextStyle(fontWeight: FontWeight.w600)),
                        if (payment.receiptUploadedAt != null)
                          Text(formatDateTime(payment.receiptUploadedAt!), style: Theme.of(context).textTheme.bodySmall),
                        if (payment.reviewedAt != null)
                          Text('Reviewed ${formatDateTime(payment.reviewedAt!)}', style: Theme.of(context).textTheme.bodySmall),
                        TextButton(
                          onPressed: () => showImageViewer(context, payment.receiptImageUrl!, title: 'Your receipt'),
                          child: const Text('View'),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              Text(AppConfig.resolveMediaUrl(payment.receiptImageUrl!), style: Theme.of(context).textTheme.labelSmall, maxLines: 1, overflow: TextOverflow.ellipsis),
            ],
          ],
        ),
      ),
    );
  }
}
