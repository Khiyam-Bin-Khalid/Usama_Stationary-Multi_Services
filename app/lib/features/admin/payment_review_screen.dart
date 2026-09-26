import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../core/config.dart';
import '../../core/format.dart';
import '../../core/providers.dart';
import '../../data/remote/api_client.dart';

final _pendingPaymentsProvider = FutureProvider.autoDispose<List<Map<String, dynamic>>>(
  (ref) => ref.watch(paymentApiProvider).pendingReview(),
);

class PaymentReviewScreen extends ConsumerWidget {
  const PaymentReviewScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final paymentsAsync = ref.watch(_pendingPaymentsProvider);

    return paymentsAsync.when(
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (e, _) => Center(child: Text('Failed to load: $e')),
      data: (payments) {
        if (payments.isEmpty) return const Center(child: Text('No payments awaiting review'));
        return ListView.builder(
          padding: const EdgeInsets.all(12),
          itemCount: payments.length,
          itemBuilder: (context, i) {
            final payment = payments[i];
            final order = payment['order'] as Map<String, dynamic>?;
            final customer = order?['customer'] as Map<String, dynamic>?;
            final receiptUrl = payment['receiptImageUrl'] != null ? '${AppConfig.mediaBaseUrl}${payment['receiptImageUrl']}' : null;

            return Card(
              margin: const EdgeInsets.only(bottom: 12),
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    if (receiptUrl != null)
                      ClipRRect(
                        borderRadius: BorderRadius.circular(8),
                        child: Image.network(receiptUrl, width: 100, height: 100, fit: BoxFit.cover,
                            errorBuilder: (context, error, stack) => const SizedBox(
                                  width: 100,
                                  height: 100,
                                  child: Icon(Icons.receipt_long_outlined),
                                )),
                      ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text('Order ${order?['orderNumber'] ?? ''}', style: Theme.of(context).textTheme.titleSmall),
                          Text(customer?['name'] ?? 'Customer'),
                          Text(formatCurrency(payment['amount'] ?? 0)),
                          const SizedBox(height: 8),
                          Row(
                            children: [
                              OutlinedButton(
                                onPressed: () => _reject(context, ref, payment['_id'] as String),
                                child: const Text('Reject'),
                              ),
                              const SizedBox(width: 8),
                              FilledButton(
                                onPressed: () => _approve(context, ref, payment['_id'] as String),
                                child: const Text('Approve'),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            );
          },
        );
      },
    );
  }

  Future<void> _approve(BuildContext context, WidgetRef ref, String paymentId) async {
    try {
      await ref.read(paymentApiProvider).review(paymentId, approve: true);
      ref.invalidate(_pendingPaymentsProvider);
    } catch (e) {
      final message = e is ApiException ? e.message : e.toString();
      if (context.mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));
    }
  }

  Future<void> _reject(BuildContext context, WidgetRef ref, String paymentId) async {
    final noteController = TextEditingController();
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Reject payment'),
        content: TextField(
          controller: noteController,
          decoration: const InputDecoration(labelText: 'Reason (shown to the customer)'),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(dialogContext, false), child: const Text('Cancel')),
          FilledButton(onPressed: () => Navigator.pop(dialogContext, true), child: const Text('Reject')),
        ],
      ),
    );
    if (confirmed != true) return;
    try {
      await ref.read(paymentApiProvider).review(paymentId, approve: false, note: noteController.text);
      ref.invalidate(_pendingPaymentsProvider);
    } catch (e) {
      final message = e is ApiException ? e.message : e.toString();
      if (context.mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));
    }
  }
}
