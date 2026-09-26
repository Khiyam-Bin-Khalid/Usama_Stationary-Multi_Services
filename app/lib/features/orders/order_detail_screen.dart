import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart';
import '../../core/format.dart';
import '../../core/providers.dart';
import '../../core/roles.dart';
import '../../core/theme/status_style.dart';
import '../../data/models/order.dart';
import '../../data/remote/api_client.dart';
import 'order_status_style.dart';

final _orderDetailProvider =
    FutureProvider.autoDispose.family<CustomerOrder, String>((ref, id) => ref.watch(orderApiProvider).myOrder(id));

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
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Receipt uploaded — awaiting admin review')));
    } catch (e) {
      final message = e is ApiException ? e.message : e.toString();
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
        final needsReceipt = order.paymentMethod == PaymentMethod.manualReceipt &&
            (order.paymentStatus == PaymentStatus.unpaid || order.paymentStatus == PaymentStatus.rejected);

        return ListView(
          padding: const EdgeInsets.all(16),
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(order.orderNumber, style: Theme.of(context).textTheme.titleLarge),
                StatusBadge(label: orderStatusLabel(order.status), tone: orderStatusTone(order.status)),
              ],
            ),
            Text(formatDateTime(order.createdAt), style: Theme.of(context).textTheme.bodySmall),
            const SizedBox(height: 16),
            StatusBadge(label: paymentStatusLabel(order.paymentStatus), tone: paymentStatusTone(order.paymentStatus)),
            if (needsReceipt) ...[
              const SizedBox(height: 12),
              Card(
                color: Theme.of(context).colorScheme.surfaceContainerHighest,
                child: Padding(
                  padding: const EdgeInsets.all(12),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text('Upload your payment receipt so an admin can confirm it.'),
                      const SizedBox(height: 8),
                      ElevatedButton.icon(
                        onPressed: _uploading ? null : _pickAndUploadReceipt,
                        icon: const Icon(Icons.upload_outlined),
                        label: Text(_uploading ? 'Uploading...' : 'Upload receipt'),
                      ),
                    ],
                  ),
                ),
              ),
            ],
            const SizedBox(height: 24),
            Text('Items', style: Theme.of(context).textTheme.titleMedium),
            for (final item in order.items)
              ListTile(
                contentPadding: EdgeInsets.zero,
                title: Text(item.name),
                subtitle: Text('${item.quantity} × ${formatCurrency(item.unitPrice)}'),
                trailing: Text(formatCurrency(item.lineTotal)),
              ),
            const Divider(),
            _SummaryRow(label: 'Subtotal', value: order.subtotal),
            if (order.discountTotal > 0) _SummaryRow(label: 'Discount', value: -order.discountTotal),
            if (order.taxAmount > 0) _SummaryRow(label: 'Tax', value: order.taxAmount),
            if (order.deliveryFee > 0) _SummaryRow(label: 'Delivery', value: order.deliveryFee),
            _SummaryRow(label: 'Total', value: order.total, emphasize: true),
          ],
        );
      },
    );
  }
}

class _SummaryRow extends StatelessWidget {
  final String label;
  final double value;
  final bool emphasize;
  const _SummaryRow({required this.label, required this.value, this.emphasize = false});

  @override
  Widget build(BuildContext context) {
    final style = emphasize ? Theme.of(context).textTheme.titleMedium : Theme.of(context).textTheme.bodyMedium;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [Text(label, style: style), Text(formatCurrency(value), style: style)],
      ),
    );
  }
}
