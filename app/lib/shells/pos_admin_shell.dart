import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../core/providers.dart';
import '../core/roles.dart';
import '../core/theme/app_colors.dart';
import '../core/theme/status_style.dart';
import '../data/repositories/sync_service.dart';

class _NavItem {
  final String path;
  final IconData icon;
  final String label;
  const _NavItem(this.path, this.icon, this.label);
}

/// Shell for the Desktop POS / Admin app. Navigation is built from the
/// spec §2 permission matrix (Permissions) so each role only sees its own
/// screens; the router additionally blocks direct navigation.
class PosAdminShell extends ConsumerWidget {
  final Widget child;
  const PosAdminShell({super.key, required this.child});

  // Consolidated spec admin navigation: dashboard, products, inventory,
  // low stock, stock movement, orders, payment review, processing &
  // delivery, staff, shifts, promotions, reports, notifications, settings —
  // each entry only for the roles whose permission row allows it.
  static List<_NavItem> _itemsFor(String role) {
    final isStaff = role == UserRole.staff;
    return [
      const _NavItem('/dashboard', Icons.dashboard_outlined, 'Dashboard'),
      const _NavItem('/pos', Icons.point_of_sale, 'Sales (POS)'),
      _NavItem('/inventory', Icons.inventory_2_outlined, isStaff ? 'Stock' : 'Products & inventory'),
      const _NavItem('/inventory/low-stock', Icons.warning_amber_outlined, 'Low stock'),
      if (Permissions.viewStockMovements(role)) const _NavItem('/inventory/movements', Icons.swap_vert_outlined, 'Stock movement'),
      _NavItem('/inventory/discrepancies', Icons.flag_outlined, isStaff ? 'My stock reports' : 'Stock reports'),
      if (Permissions.manageOrders(role)) const _NavItem('/admin/orders', Icons.shopping_bag_outlined, 'Orders'),
      if (Permissions.reviewPayments(role)) const _NavItem('/admin/payments', Icons.receipt_long_outlined, 'Payment review'),
      if (Permissions.manageDelivery(role)) const _NavItem('/admin/delivery', Icons.local_shipping_outlined, 'Processing & delivery'),
      if (Permissions.manageAccounts(role)) const _NavItem('/admin/staff', Icons.manage_accounts_outlined, 'Staff & roles'),
      const _NavItem('/shift', Icons.schedule_outlined, 'Shifts'),
      if (Permissions.managePromotions(role)) const _NavItem('/admin/promotions', Icons.local_offer_outlined, 'Deals & promotions'),
      _NavItem('/reports', Icons.show_chart_outlined, isStaff ? 'My sales' : 'Reports'),
      if (Permissions.viewAuditLog(role)) const _NavItem('/admin/audit-log', Icons.history_outlined, 'Audit log'),
      const _NavItem('/notifications', Icons.notifications_outlined, 'Notifications'),
      const _NavItem('/settings', Icons.settings_outlined, 'Settings'),
    ];
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final user = ref.watch(authStateProvider).valueOrNull;
    final role = user?.role ?? UserRole.staff;
    final items = _itemsFor(role);
    final location = GoRouterState.of(context).matchedLocation;
    // Longest-prefix match so /inventory/discrepancies selects its own entry.
    var selectedIndex = 0;
    var bestLen = -1;
    for (var i = 0; i < items.length; i++) {
      final p = items[i].path;
      if ((location == p || location.startsWith('$p/')) && p.length > bestLen) {
        selectedIndex = i;
        bestLen = items[i].path.length;
      }
    }

    final isWide = MediaQuery.of(context).size.width >= 900;
    final syncService = ref.watch(syncServiceProvider);
    final unread = ref.watch(unreadNotificationsProvider).valueOrNull ?? 0;

    final sidebar = _Sidebar(
      items: items,
      selectedIndex: selectedIndex,
      userName: user?.name ?? '',
      role: role,
      unread: unread,
      syncService: syncService,
      onSelect: (i) {
        if (!isWide) Navigator.of(context).pop(); // close drawer
        context.go(items[i].path);
      },
      onLogout: () => ref.read(authStateProvider.notifier).logout(),
    );

    return Scaffold(
      appBar: isWide
          ? null
          : AppBar(
              title: Text(items[selectedIndex].label),
              actions: [
                IconButton(
                  icon: Badge(label: Text('$unread'), isLabelVisible: unread > 0, child: const Icon(Icons.notifications_outlined)),
                  onPressed: () => context.go('/notifications'),
                ),
              ],
            ),
      drawer: isWide ? null : Drawer(child: SafeArea(child: sidebar)),
      body: Column(
        children: [
          if (syncService != null) _SyncBanner(syncService: syncService),
          Expanded(
            child: Row(
              children: [
                if (isWide) SizedBox(width: 232, child: sidebar),
                if (isWide) const VerticalDivider(),
                Expanded(child: child),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _Sidebar extends StatelessWidget {
  final List<_NavItem> items;
  final int selectedIndex;
  final String userName;
  final String role;
  final int unread;
  final SyncService? syncService;
  final void Function(int) onSelect;
  final VoidCallback onLogout;

  const _Sidebar({
    required this.items,
    required this.selectedIndex,
    required this.userName,
    required this.role,
    required this.unread,
    required this.syncService,
    required this.onSelect,
    required this.onLogout,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      color: AppColors.surface,
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 20, 16, 12),
            child: Row(
              children: [
                const Icon(Icons.storefront_outlined, size: 28, color: AppColors.primaryOrange),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(userName, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.w700)),
                      Text(UserRole.label(role), style: Theme.of(context).textTheme.labelSmall),
                    ],
                  ),
                ),
              ],
            ),
          ),
          const Divider(),
          Expanded(
            child: ListView.builder(
              padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 8),
              itemCount: items.length,
              itemBuilder: (context, i) {
                final item = items[i];
                final selected = i == selectedIndex;
                final showBadge = item.path == '/notifications' && unread > 0;
                return Padding(
                  padding: const EdgeInsets.symmetric(vertical: 2),
                  child: Material(
                    color: selected ? AppColors.tint(AppColors.primaryOrange) : Colors.transparent,
                    borderRadius: BorderRadius.circular(10),
                    child: InkWell(
                      borderRadius: BorderRadius.circular(10),
                      onTap: () => onSelect(i),
                      child: Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                        child: Row(
                          children: [
                            Badge(
                              label: Text('$unread'),
                              isLabelVisible: showBadge,
                              child: Icon(item.icon, size: 22, color: selected ? AppColors.primaryOrange : AppColors.textSecondary),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Text(
                                item.label,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(
                                  fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
                                  color: selected ? AppColors.primaryOrange : AppColors.textPrimary,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                );
              },
            ),
          ),
          const Divider(),
          if (syncService != null) _SyncIndicator(syncService: syncService!),
          Padding(
            padding: const EdgeInsets.fromLTRB(8, 4, 8, 12),
            child: SizedBox(
              width: double.infinity,
              child: TextButton.icon(
                onPressed: onLogout,
                icon: const Icon(Icons.logout, size: 18),
                label: const Text('Log out'),
                style: TextButton.styleFrom(foregroundColor: AppColors.textSecondary, alignment: Alignment.centerLeft),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Small "synced with server" dot (success) / syncing (orange) / offline (red).
class _SyncIndicator extends StatelessWidget {
  final SyncService syncService;
  const _SyncIndicator({required this.syncService});

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<SyncStatus>(
      stream: syncService.statusStream,
      builder: (context, snapshot) {
        final status = snapshot.data ?? SyncStatus.idle;
        final (color, label) = switch (status) {
          SyncStatus.idle => (AppColors.success, 'Synced with server'),
          SyncStatus.syncing => (AppColors.primaryOrange, 'Syncing…'),
          SyncStatus.offline => (AppColors.accentRed, 'Offline — queuing sales'),
        };
        return Padding(
          padding: const EdgeInsets.fromLTRB(20, 10, 16, 4),
          child: Row(
            children: [
              StatusDot(color: color),
              const SizedBox(width: 8),
              Expanded(child: Text(label, style: Theme.of(context).textTheme.labelSmall, maxLines: 1, overflow: TextOverflow.ellipsis)),
            ],
          ),
        );
      },
    );
  }
}

class _SyncBanner extends StatelessWidget {
  final SyncService syncService;
  const _SyncBanner({required this.syncService});

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<SyncStatus>(
      stream: syncService.statusStream,
      builder: (context, snapshot) {
        if (snapshot.data != SyncStatus.offline) return const SizedBox.shrink();
        return Container(
          width: double.infinity,
          color: AppColors.tint(AppColors.accentRed),
          padding: const EdgeInsets.symmetric(vertical: 6, horizontal: 12),
          child: const Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.cloud_off, size: 16, color: AppColors.accentRed),
              SizedBox(width: 8),
              Text(
                'Offline — sales are being saved locally and will sync automatically',
                style: TextStyle(color: AppColors.accentRed, fontSize: 12, fontWeight: FontWeight.w600),
              ),
            ],
          ),
        );
      },
    );
  }
}
