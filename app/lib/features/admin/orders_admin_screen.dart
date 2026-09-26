import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../core/format.dart';
import '../../core/providers.dart';
import '../../core/roles.dart';
import '../../core/theme/status_style.dart';
import '../../data/models/order.dart';
import '../../data/remote/api_client.dart';
import '../orders/order_status_style.dart';

final _adminOrdersProvider = FutureProvider.autoDispose.family<List<CustomerOrder>, String?>(
  (ref, status) => ref.watch(orderApiProvider).listAll(status: status),
);

class OrdersAdminScreen extends ConsumerStatefulWidget {
  const OrdersAdminScreen({super.key});

  @override
  ConsumerState<OrdersAdminScreen> createState() => _OrdersAdminScreenState();
}

class _OrdersAdminScreenState extends ConsumerState<OrdersAdminScreen> {
  String? _statusFilter;

  static const _statuses = [
    OrderStatus.pending,
    OrderStatus.confirmed,
    OrderStatus.processing,
    OrderStatus.outForDelivery,
    OrderStatus.delivered,
    OrderStatus.cancelled,
  ];

  @override
  Widget build(BuildContext context) {
    final ordersAsync = ref.watch(_adminOrdersProvider(_statusFilter));

    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.all(12),
          child: SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              children: [
                ChoiceChip(label: const Text('All'), selected: _statusFilter == null, onSelected: (_) => setState(() => _statusFilter = null)),
                const SizedBox(width: 6),
                for (final s in _statuses) ...[
                  ChoiceChip(
                    label: Text(orderStatusLabel(s)),
                    selected: _statusFilter == s,
                    onSelected: (_) => setState(() => _statusFilter = s),
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
              if (orders.isEmpty) return const Center(child: Text('No orders'));
              return ListView.separated(
                itemCount: orders.length,
                separatorBuilder: (_, __) => const Divider(height: 1),
                itemBuilder: (context, i) {
                  final o = orders[i];
                  return ListTile(
                    title: Text('${o.orderNumber} · ${formatCurrency(o.total)}'),
                    subtitle: Text('${formatDateTime(o.createdAt)} · ${o.items.length} item(s) · payment: ${o.paymentStatus}'),
                    trailing: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        StatusBadge(label: orderStatusLabel(o.status), tone: orderStatusTone(o.status)),
                        PopupMenuButton<String>(
                          onSelected: (status) => _updateStatus(o.id, status),
                          itemBuilder: (context) =>
                              [for (final s in _statuses) PopupMenuItem(value: s, child: Text('Mark as ${orderStatusLabel(s)}'))],
                        ),
                      ],
                    ),
                  );
                },
              );
            },
          ),
        ),
      ],
    );
  }

  Future<void> _updateStatus(String orderId, String status) async {
    try {
      await ref.read(orderApiProvider).updateStatus(orderId, status: status);
      ref.invalidate(_adminOrdersProvider);
    } catch (e) {
      final message = e is ApiException ? e.message : e.toString();
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));
    }
  }
}
