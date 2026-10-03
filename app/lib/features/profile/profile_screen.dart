import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../core/config.dart';
import '../../core/format.dart';
import '../../core/providers.dart';
import '../../core/responsive.dart';
import '../../core/roles.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/status_style.dart';
import '../../data/models/notification.dart';

final _myNotificationsProvider = FutureProvider.autoDispose<List<AppNotification>>((ref) => ref.watch(notificationApiProvider).list());

/// Profile / settings: account details, the signed-in role, connection info
/// and (for customers) their order + payment notifications.
class ProfileScreen extends ConsumerWidget {
  const ProfileScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final user = ref.watch(authStateProvider).valueOrNull;
    final isCustomer = user?.role == UserRole.customer;
    final notificationsAsync = ref.watch(_myNotificationsProvider);

    return SingleChildScrollView(
      child: ResponsiveContainer(
        maxWidth: 760,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(isCustomer ? 'My profile' : 'Settings', style: Theme.of(context).textTheme.headlineSmall),
            const SizedBox(height: 16),
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Row(
                  children: [
                    CircleAvatar(
                      radius: 28,
                      backgroundColor: AppColors.tint(AppColors.primaryOrange),
                      child: Text((user?.name.isNotEmpty ?? false) ? user!.name[0].toUpperCase() : '?',
                          style: const TextStyle(color: AppColors.primaryDark, fontWeight: FontWeight.w800, fontSize: 22)),
                    ),
                    const SizedBox(width: 16),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(user?.name ?? '', style: Theme.of(context).textTheme.titleMedium),
                          Text(user?.email ?? '', style: Theme.of(context).textTheme.bodySmall),
                          if (user?.phone != null && user!.phone!.isNotEmpty) Text(user.phone!, style: Theme.of(context).textTheme.bodySmall),
                          if (user?.branch != null && user!.branch!.isNotEmpty) Text('Branch: ${user.branch}', style: Theme.of(context).textTheme.bodySmall),
                        ],
                      ),
                    ),
                    StatusBadge(label: UserRole.label(user?.role ?? ''), tone: StatusTone.warning),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 16),
            if (isCustomer) ...[
              Card(
                child: Column(
                  children: [
                    ListTile(
                      leading: const Icon(Icons.receipt_long_outlined),
                      title: const Text('My orders'),
                      trailing: const Icon(Icons.chevron_right),
                      onTap: () => context.go('/orders'),
                    ),
                    const Divider(height: 1),
                    ListTile(
                      leading: const Icon(Icons.shopping_cart_outlined),
                      title: const Text('My cart'),
                      trailing: const Icon(Icons.chevron_right),
                      onTap: () => context.go('/cart'),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 16),
              Text('Notifications', style: Theme.of(context).textTheme.titleMedium),
              const SizedBox(height: 8),
              notificationsAsync.when(
                loading: () => const Padding(padding: EdgeInsets.all(16), child: Center(child: CircularProgressIndicator())),
                error: (e, _) => Text('Could not load notifications: $e'),
                data: (items) => items.isEmpty
                    ? Text('No notifications yet.', style: Theme.of(context).textTheme.bodySmall)
                    : Card(
                        child: Column(
                          children: [
                            for (var i = 0; i < items.length; i++) ...[
                              if (i > 0) const Divider(height: 1),
                              ListTile(
                                leading: Icon(
                                  items[i].type == NotificationType.paymentRejected ? Icons.error_outline : Icons.notifications_outlined,
                                  color: items[i].type == NotificationType.paymentRejected ? AppColors.accentRed : AppColors.primaryOrange,
                                ),
                                title: Text(items[i].title, style: TextStyle(fontWeight: items[i].isRead ? FontWeight.w500 : FontWeight.w700)),
                                subtitle: Text('${items[i].message}\n${formatDateTime(items[i].createdAt)}'),
                                isThreeLine: true,
                                onTap: () async {
                                  if (!items[i].isRead) await ref.read(notificationApiProvider).markRead(items[i].id);
                                  ref.invalidate(_myNotificationsProvider);
                                  final orderId = items[i].payload['orderId'];
                                  if (orderId is String && context.mounted) context.go('/orders/$orderId');
                                },
                              ),
                            ],
                          ],
                        ),
                      ),
              ),
              const SizedBox(height: 16),
            ],
            Card(
              child: Column(
                children: [
                  ListTile(
                    leading: const Icon(Icons.cloud_outlined),
                    title: const Text('Server'),
                    subtitle: Text(AppConfig.apiBaseUrl),
                  ),
                  const Divider(height: 1),
                  ListTile(
                    leading: const Icon(Icons.logout, color: AppColors.accentRed),
                    title: const Text('Log out', style: TextStyle(color: AppColors.accentRed)),
                    onTap: () => ref.read(authStateProvider.notifier).logout(),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
