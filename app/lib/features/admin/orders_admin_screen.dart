import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../core/format.dart';
import '../../core/providers.dart';
import '../../core/roles.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/status_style.dart';
import '../../data/models/order.dart';
import '../../widgets/order_widgets.dart';
import '../orders/order_status_style.dart';

final adminOrdersProvider = FutureProvider.autoDispose.family<List<CustomerOrder>, String?>(
  (ref, queueKey) {
    final queue = OrderQueue.all.where((q) => q.key == queueKey).firstOrNull;
    return ref.watch(orderApiProvider).listAll(statuses: queue?.statuses);
  },
);
final orderStatusCountsProvider = FutureProvider.autoDispose<Map<String, int>>((ref) => ref.watch(orderApiProvider).statusCounts());

/// Order management: queues for every lifecycle stage (new, payment review,
/// confirmed, processing, packing, dispatched, delivered, completed,
/// cancelled/rejected). Each row shows the ordered product images; tapping
/// opens the full order (customer, items, payment + receipt, actions).
/// [initialQueue] lets the nav open straight on e.g. the dispatch queue.
class OrdersAdminScreen extends ConsumerStatefulWidget {
  final String? initialQueue;
  final String? title;
  const OrdersAdminScreen({super.key, this.initialQueue, this.title});

  @override
  ConsumerState<OrdersAdminScreen> createState() => _OrdersAdminScreenState();
}

class _OrdersAdminScreenState extends ConsumerState<OrdersAdminScreen> {
  String? _queue;

  @override
  void initState() {
    super.initState();
    _queue = widget.initialQueue;
  }

  @override
  void didUpdateWidget(covariant OrdersAdminScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.initialQueue != widget.initialQueue) _queue = widget.initialQueue;
  }

  int _count(Map<String, int> counts, OrderQueue q) => q.statuses.fold(0, (s, st) => s + (counts[st] ?? 0));

  @override
  Widget build(BuildContext context) {
    final ordersAsync = ref.watch(adminOrdersProvider(_queue));
    final counts = ref.watch(orderStatusCountsProvider).valueOrNull ?? const <String, int>{};
    final total = counts.values.fold(0, (a, b) => a + b);

    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
          child: Row(
            children: [
              Text(widget.title ?? 'Orders', style: Theme.of(context).textTheme.titleLarge),
              const Spacer(),
              IconButton(
                icon: const Icon(Icons.refresh),
                onPressed: () {
                  ref.invalidate(adminOrdersProvider);
                  ref.invalidate(orderStatusCountsProvider);
                },
              ),
            ],
          ),
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          child: SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              children: [
                ChoiceChip(label: Text('All ($total)'), selected: _queue == null, onSelected: (_) => setState(() => _queue = null)),
                const SizedBox(width: 6),
                for (final q in OrderQueue.all) ...[
                  ChoiceChip(
                    label: Text('${q.label} (${_count(counts, q)})'),
                    selected: _queue == q.key,
                    onSelected: (_) => setState(() => _queue = q.key),
                  ),
                  const SizedBox(width: 6),
                ],
              ],
            ),
          ),
        ),
        Expanded(
          child: ordersAsync.when(
            loading: () => const Center(child: CircularProgressIndicator()),
            error: (e, _) => Center(child: Text('Failed to load: $e')),
            data: (orders) {
              if (orders.isEmpty) return const Center(child: Text('No orders in this queue'));
              return ListView.separated(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
                itemCount: orders.length,
                separatorBuilder: (_, __) => const Divider(height: 1),
                itemBuilder: (context, i) => _OrderRow(order: orders[i]),
              );
            },
          ),
        ),
      ],
    );
  }
}

class _OrderRow extends StatelessWidget {
  final CustomerOrder order;
  const _OrderRow({required this.order});

  @override
  Widget build(BuildContext context) {
    final reviewNeeded = order.paymentStatus == PaymentStatus.pendingReview && order.paymentMethod == PaymentMethod.manualReceipt;
    return InkWell(
      onTap: () => context.go('/admin/orders/${order.id}'),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 10),
        child: Row(
          children: [
            OrderThumbnails(items: order.items),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('${order.orderNumber} · ${formatCurrency(order.total)}', style: const TextStyle(fontWeight: FontWeight.w700)),
                  Text(
                    '${order.customer?.name ?? 'Customer'} · ${formatDateTime(order.createdAt)} · ${order.itemCount} item(s) · ${paymentMethodLabel(order.paymentMethod)}',
                    style: Theme.of(context).textTheme.bodySmall,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 6),
                  Wrap(
                    spacing: 6,
                    runSpacing: 4,
                    children: [
                      StatusBadge(label: orderStatusLabel(order.status), tone: orderStatusTone(order.status)),
                      StatusBadge(label: paymentStatusLabel(order.paymentStatus), tone: paymentStatusTone(order.paymentStatus)),
                      if (reviewNeeded) const StatusBadge(label: 'Receipt to verify', tone: StatusTone.danger, solid: true),
                    ],
                  ),
                ],
              ),
            ),
            const Icon(Icons.chevron_right, color: AppColors.textSecondary),
          ],
        ),
      ),
    );
  }
}
