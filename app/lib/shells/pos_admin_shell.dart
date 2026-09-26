import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../core/providers.dart';
import '../core/roles.dart';
import '../data/repositories/sync_service.dart';

class _NavItem {
  final String path;
  final IconData icon;
  final String label;
  const _NavItem(this.path, this.icon, this.label);
}

class PosAdminShell extends ConsumerWidget {
  final Widget child;
  const PosAdminShell({super.key, required this.child});

  List<_NavItem> _itemsFor(String role) {
    final items = <_NavItem>[const _NavItem('/pos', Icons.point_of_sale, 'POS')];
    if (role != UserRole.staff) {
      items.add(const _NavItem('/inventory', Icons.inventory_2_outlined, 'Inventory'));
    } else {
      items.add(const _NavItem('/inventory', Icons.inventory_2_outlined, 'Stock'));
    }
    items.add(const _NavItem('/reports', Icons.bar_chart_outlined, 'Reports'));
    if (role == UserRole.admin || role == UserRole.superadmin) {
      items.add(const _NavItem('/admin/orders', Icons.local_shipping_outlined, 'Orders'));
      items.add(const _NavItem('/admin/payments', Icons.receipt_long_outlined, 'Payments'));
      items.add(const _NavItem('/admin/promotions', Icons.local_offer_outlined, 'Promotions'));
      items.add(const _NavItem('/admin/staff', Icons.people_outline, 'Staff'));
    }
    return items;
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final user = ref.watch(authStateProvider).valueOrNull;
    final role = user?.role ?? UserRole.staff;
    final items = _itemsFor(role);
    final location = GoRouterState.of(context).matchedLocation;
    final selectedIndex = items.indexWhere((i) => location.startsWith(i.path)).clamp(0, items.length - 1);

    final isWide = MediaQuery.of(context).size.width >= 900;

    final syncService = ref.watch(syncServiceProvider);

    final content = Row(
      children: [
        if (isWide)
          NavigationRail(
            selectedIndex: selectedIndex,
            onDestinationSelected: (i) => context.go(items[i].path),
            labelType: NavigationRailLabelType.all,
            leading: Padding(
              padding: const EdgeInsets.symmetric(vertical: 16),
              child: Column(
                children: [
                  const Icon(Icons.storefront_outlined, size: 32),
                  const SizedBox(height: 8),
                  Text(user?.name ?? '', style: Theme.of(context).textTheme.labelMedium, textAlign: TextAlign.center),
                  Text(role.toUpperCase(), style: Theme.of(context).textTheme.labelSmall),
                ],
              ),
            ),
            trailing: Expanded(
              child: Align(
                alignment: Alignment.bottomCenter,
                child: Padding(
                  padding: const EdgeInsets.only(bottom: 16),
                  child: IconButton(
                    icon: const Icon(Icons.logout),
                    tooltip: 'Log out',
                    onPressed: () => ref.read(authStateProvider.notifier).logout(),
                  ),
                ),
              ),
            ),
            destinations: [
              for (final item in items) NavigationRailDestination(icon: Icon(item.icon), label: Text(item.label)),
            ],
          ),
        Expanded(child: child),
      ],
    );

    return Scaffold(
      appBar: isWide
          ? null
          : AppBar(
              title: Text(items[selectedIndex].label),
              actions: [
                IconButton(icon: const Icon(Icons.logout), onPressed: () => ref.read(authStateProvider.notifier).logout()),
              ],
            ),
      body: Column(
        children: [
          if (syncService != null) _SyncBanner(syncService: syncService),
          Expanded(child: content),
        ],
      ),
      bottomNavigationBar: isWide
          ? null
          : NavigationBar(
              selectedIndex: selectedIndex,
              onDestinationSelected: (i) => context.go(items[i].path),
              destinations: [
                for (final item in items) NavigationDestination(icon: Icon(item.icon), label: item.label),
              ],
            ),
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
        final status = snapshot.data;
        if (status != SyncStatus.offline) return const SizedBox.shrink();
        return Container(
          width: double.infinity,
          color: Theme.of(context).colorScheme.errorContainer,
          padding: const EdgeInsets.symmetric(vertical: 6, horizontal: 12),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.cloud_off, size: 16, color: Theme.of(context).colorScheme.onErrorContainer),
              const SizedBox(width: 8),
              Text(
                'Offline — sales are being saved locally and will sync automatically',
                style: TextStyle(color: Theme.of(context).colorScheme.onErrorContainer, fontSize: 12),
              ),
            ],
          ),
        );
      },
    );
  }
}
