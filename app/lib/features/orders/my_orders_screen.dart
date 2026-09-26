import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../core/format.dart';
import '../../core/providers.dart';
import '../../core/theme/status_style.dart';
import '../../data/models/order.dart';
import 'order_status_style.dart';

final _myOrdersProvider = FutureProvider.autoDispose<List<CustomerOrder>>((ref) => ref.watch(orderApiProvider).myOrders());

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
          if (orders.isEmpty) return const Center(child: Text('You have not placed any orders yet'));
          return ListView.separated(
            itemCount: orders.length,
            separatorBuilder: (_, __) => const Divider(height: 1),
            itemBuilder: (context, i) {
              final o = orders[i];
              return ListTile(
                title: Text('${o.orderNumber} · ${formatCurrency(o.total)}'),
                subtitle: Text(formatDateTime(o.createdAt)),
                trailing: StatusBadge(label: orderStatusLabel(o.status), tone: orderStatusTone(o.status)),
                onTap: () => context.go('/orders/${o.id}'),
              );
            },
          );
        },
      ),
    );
  }
}
