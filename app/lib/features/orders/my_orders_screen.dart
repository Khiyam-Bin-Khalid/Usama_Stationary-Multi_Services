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
import 'order_status_style.dart';

final _myOrdersProvider = FutureProvider.autoDispose<List<CustomerOrder>>((ref) => ref.watch(orderApiProvider).myOrders());

/// Order history: each row shows the product images that were ordered, the
/// order number, date, total and both statuses.
class MyOrdersScreen extends ConsumerWidget {
  const MyOrdersScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final ordersAsync = ref.watch(_myOrdersProvider);

    return RefreshIndicator(
      onRefresh: () async => ref.invalidate(_myOrdersProvider),
      child: ordersAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(child: Text('Could not load orders: $e')),
        data: (orders) {
          if (orders.isEmpty) {
            return ListView(
              children: [
                ResponsiveContainer(
                  child: Column(
                    children: [
                      const SizedBox(height: 48),
                      const Icon(Icons.receipt_long_outlined, size: 56, color: AppColors.textSecondary),
                      const SizedBox(height: 12),
                      const Text('You have not placed any orders yet'),
                      const SizedBox(height: 16),
                      FilledButton(onPressed: () => context.go('/shop'), child: const Text('Start shopping')),
                    ],
                  ),
                ),
              ],
            );
          }
          return ListView(
            children: [
              ResponsiveContainer(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('My orders', style: Theme.of(context).textTheme.headlineSmall),
                    const SizedBox(height: 12),
                    for (final o in orders) _OrderRow(order: o),
                  ],
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}

class _OrderRow extends StatelessWidget {
  final CustomerOrder order;
  const _OrderRow({required this.order});

  @override
  Widget build(BuildContext context) {
    final needsAction = order.paymentMethod == PaymentMethod.manualReceipt &&
        (order.paymentStatus == PaymentStatus.unpaid || order.paymentStatus == PaymentStatus.rejected) &&
        !OrderStatus.isTerminal(order.status);
    return Card(
      margin: const EdgeInsets.only(bottom: 10),
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: () => context.go('/orders/${order.id}'),
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Row(
            children: [
              OrderThumbnails(items: order.items),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('${order.orderNumber} · ${formatCurrency(order.total)}', style: const TextStyle(fontWeight: FontWeight.w700)),
                    Text('${formatDateTime(order.createdAt)} · ${order.itemCount} item(s)', style: Theme.of(context).textTheme.bodySmall),
                    const SizedBox(height: 6),
                    Wrap(
                      spacing: 6,
                      runSpacing: 4,
                      children: [
                        StatusBadge(label: orderStatusLabel(order.status), tone: orderStatusTone(order.status)),
                        if (needsAction) const StatusBadge(label: 'Upload receipt', tone: StatusTone.danger, solid: true),
                      ],
                    ),
                  ],
                ),
              ),
              const Icon(Icons.chevron_right, color: AppColors.textSecondary),
            ],
          ),
        ),
      ),
    );
  }
}
