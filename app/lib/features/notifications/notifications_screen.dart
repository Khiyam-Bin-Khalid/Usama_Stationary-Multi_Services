import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../core/format.dart';
import '../../core/providers.dart';
import '../../core/roles.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/status_style.dart';
import '../../data/models/notification.dart';

final _notificationsProvider = FutureProvider.autoDispose<List<AppNotification>>((ref) => ref.watch(notificationApiProvider).list());

class NotificationsScreen extends ConsumerWidget {
  const NotificationsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final listAsync = ref.watch(_notificationsProvider);

    void refresh() {
      ref.invalidate(_notificationsProvider);
      ref.invalidate(unreadNotificationsProvider);
    }

    return Scaffold(
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
            child: Row(
              children: [
                Text('Alerts', style: Theme.of(context).textTheme.titleLarge),
                const Spacer(),
                TextButton.icon(
                  onPressed: () async {
                    await ref.read(notificationApiProvider).markAllRead();
                    refresh();
                  },
                  icon: const Icon(Icons.done_all, size: 18),
                  label: const Text('Mark all read'),
                ),
                IconButton(icon: const Icon(Icons.refresh), onPressed: refresh),
              ],
            ),
          ),
          Expanded(
            child: listAsync.when(
              loading: () => const Center(child: CircularProgressIndicator()),
              error: (e, _) => Center(child: Text('Failed to load: $e')),
              data: (items) {
                if (items.isEmpty) {
                  return const Center(child: Text('No alerts — you\'re all caught up'));
                }
                return ListView.separated(
                  itemCount: items.length,
                  separatorBuilder: (_, __) => const Divider(),
                  itemBuilder: (context, i) {
                    final n = items[i];
                    final style = _styleFor(n.type);
                    return ListTile(
                      tileColor: n.isRead ? null : AppColors.surface,
                      leading: Container(
                        width: 40,
                        height: 40,
                        decoration: BoxDecoration(color: AppColors.tint(style.$2), borderRadius: BorderRadius.circular(10)),
                        child: Icon(style.$1, color: style.$2),
                      ),
                      title: Text(n.title, style: TextStyle(fontWeight: n.isRead ? FontWeight.w500 : FontWeight.w700)),
                      subtitle: Text('${n.message}\n${formatDateTime(n.createdAt)}'),
                      isThreeLine: true,
                      trailing: n.isRead ? null : const StatusDot(color: AppColors.accentRed, size: 10),
                      onTap: () async {
                        if (!n.isRead) {
                          await ref.read(notificationApiProvider).markRead(n.id);
                          refresh();
                        }
                        if (!context.mounted) return;
                        final orderId = n.payload['orderId'];
                        if (n.type == NotificationType.paymentReviewRequired) {
                          context.go('/admin/payments');
                        } else if (orderId is String && (n.type == NotificationType.orderPlaced)) {
                          context.go('/admin/orders/$orderId');
                        } else if (n.type == NotificationType.lowStock || n.type == NotificationType.outOfStock) {
                          context.go('/inventory/low-stock');
                        }
                      },
                    );
                  },
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  (IconData, Color) _styleFor(String type) {
    switch (type) {
      case NotificationType.lowStock:
        return (Icons.warning_amber_outlined, AppColors.accentRed);
      case NotificationType.outOfStock:
        return (Icons.remove_shopping_cart_outlined, AppColors.accentRed);
      case NotificationType.paymentFailed:
        return (Icons.credit_card_off_outlined, AppColors.accentRed);
      case NotificationType.syncFailed:
        return (Icons.cloud_off_outlined, AppColors.accentRed);
      case NotificationType.inventoryDiscrepancy:
        return (Icons.flag_outlined, AppColors.primaryOrange);
      case NotificationType.orderPlaced:
        return (Icons.shopping_bag_outlined, AppColors.primaryOrange);
      case NotificationType.paymentReviewRequired:
        return (Icons.receipt_long_outlined, AppColors.primaryOrange);
      case NotificationType.paymentRejected:
        return (Icons.money_off_csred_outlined, AppColors.accentRed);
      case NotificationType.paymentApproved:
        return (Icons.price_check_outlined, AppColors.success);
      case NotificationType.orderStatusChanged:
        return (Icons.local_shipping_outlined, AppColors.primaryOrange);
      case NotificationType.customerRegistered:
        return (Icons.person_add_alt_outlined, AppColors.success);
      default:
        return (Icons.notifications_outlined, AppColors.textSecondary);
    }
  }
}
