import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../core/format.dart';
import '../../core/providers.dart';
import '../../core/roles.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/status_style.dart';

final dashboardProvider = FutureProvider.autoDispose<Map<String, dynamic>>((ref) => ref.watch(reportApiProvider).dashboard());

/// Spec §1: each role lands on a *different* dashboard, not one screen with
/// hidden buttons. The server returns only the sections the role may see.
class DashboardScreen extends ConsumerWidget {
  const DashboardScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final user = ref.watch(authStateProvider).valueOrNull;
    final role = user?.role ?? UserRole.staff;
    final dataAsync = ref.watch(dashboardProvider);

    return RefreshIndicator(
      onRefresh: () async => ref.invalidate(dashboardProvider),
      child: dataAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => ListView(children: [Padding(padding: const EdgeInsets.all(24), child: Text('Could not load dashboard: $e'))]),
        data: (data) {
          final body = switch (role) {
            UserRole.superadmin => _SuperAdminDashboard(data: data),
            UserRole.admin => _AdminDashboard(data: data),
            _ => _StaffDashboard(data: data),
          };
          return ListView(
            padding: const EdgeInsets.all(20),
            children: [
              Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('Hello, ${user?.name ?? ''}', style: Theme.of(context).textTheme.headlineSmall),
                        Text('${UserRole.label(role)} dashboard · ${formatDateTime(DateTime.now())}',
                            style: Theme.of(context).textTheme.bodySmall),
                      ],
                    ),
                  ),
                  StatusBadge(label: UserRole.label(role), tone: StatusTone.warning),
                ],
              ),
              const SizedBox(height: 20),
              body,
            ],
          );
        },
      ),
    );
  }
}

// ---------------------------------------------------------------- Staff

class _StaffDashboard extends StatelessWidget {
  final Map<String, dynamic> data;
  const _StaffDashboard({required this.data});

  @override
  Widget build(BuildContext context) {
    final mine = Map<String, dynamic>.from(data['mySalesToday'] as Map? ?? {});
    final shift = data['shift'] as Map<String, dynamic>?;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _ShiftCard(shift: shift),
        const SizedBox(height: 16),
        _StatGrid(tiles: [
          _StatTile(label: 'My sales today', value: '${mine['salesCount'] ?? 0}', icon: Icons.receipt_long_outlined),
          _StatTile(label: 'My revenue today', value: formatCurrency(mine['totalRevenue'] ?? 0), icon: Icons.payments_outlined),
          _StatTile(label: 'Items sold', value: '${mine['totalItemsSold'] ?? 0}', icon: Icons.shopping_bag_outlined),
          _StatTile(
            label: 'My open stock reports',
            value: '${data['openDiscrepancies'] ?? 0}',
            icon: Icons.flag_outlined,
            accent: (data['openDiscrepancies'] ?? 0) > 0 ? AppColors.primaryOrange : null,
          ),
        ]),
        const SizedBox(height: 24),
        const _SectionTitle('Quick actions'),
        const SizedBox(height: 8),
        const _QuickActions(actions: [
          _Action('New sale', Icons.point_of_sale, '/pos', primary: true),
          _Action('Check stock', Icons.inventory_2_outlined, '/inventory'),
          _Action('My stock reports', Icons.flag_outlined, '/inventory/discrepancies'),
          _Action('My sales', Icons.bar_chart_outlined, '/reports'),
        ]),
        const SizedBox(height: 16),
        Text(
          'Staff can view stock and report discrepancies; corrections are applied by an Admin.',
          style: Theme.of(context).textTheme.bodySmall,
        ),
      ],
    );
  }
}

// ---------------------------------------------------------------- Admin

class _AdminDashboard extends StatelessWidget {
  final Map<String, dynamic> data;
  const _AdminDashboard({required this.data});

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _StoreStats(data: data),
        const SizedBox(height: 24),
        const _SectionTitle('Quick actions'),
        const SizedBox(height: 8),
        const _QuickActions(actions: [
          _Action('New sale', Icons.point_of_sale, '/pos', primary: true),
          _Action('Add product', Icons.add_box_outlined, '/inventory'),
          _Action('Orders', Icons.local_shipping_outlined, '/admin/orders'),
          _Action('Payments', Icons.receipt_long_outlined, '/admin/payments'),
          _Action('Promotions', Icons.local_offer_outlined, '/admin/promotions'),
          _Action('Reports', Icons.bar_chart_outlined, '/reports'),
        ]),
        const SizedBox(height: 24),
        _CategoryBreakdown(data: data),
      ],
    );
  }
}

// ---------------------------------------------------------------- Super Admin

class _SuperAdminDashboard extends StatelessWidget {
  final Map<String, dynamic> data;
  const _SuperAdminDashboard({required this.data});

  @override
  Widget build(BuildContext context) {
    final accounts = Map<String, dynamic>.from(data['accounts'] as Map? ?? {});
    final audit = (data['recentAudit'] as List? ?? []).cast<Map<String, dynamic>>();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _StoreStats(data: data),
        const SizedBox(height: 16),
        _StatGrid(tiles: [
          _StatTile(label: 'Admins', value: '${accounts['admins'] ?? 0}', icon: Icons.admin_panel_settings_outlined),
          _StatTile(label: 'Staff', value: '${accounts['staff'] ?? 0}', icon: Icons.badge_outlined),
          _StatTile(label: 'Customers', value: '${accounts['customers'] ?? 0}', icon: Icons.people_outline),
        ]),
        const SizedBox(height: 24),
        const _SectionTitle('Quick actions'),
        const SizedBox(height: 8),
        const _QuickActions(actions: [
          _Action('New sale', Icons.point_of_sale, '/pos', primary: true),
          _Action('Accounts & roles', Icons.manage_accounts_outlined, '/admin/staff'),
          _Action('Audit log', Icons.history_outlined, '/admin/audit-log'),
          _Action('Inventory', Icons.inventory_2_outlined, '/inventory'),
          _Action('Orders', Icons.local_shipping_outlined, '/admin/orders'),
          _Action('Reports', Icons.bar_chart_outlined, '/reports'),
        ]),
        const SizedBox(height: 24),
        _CategoryBreakdown(data: data),
        const SizedBox(height: 24),
        const _SectionTitle('Recent activity (audit log)'),
        const SizedBox(height: 8),
        Card(
          child: audit.isEmpty
              ? const Padding(padding: EdgeInsets.all(16), child: Text('No activity yet'))
              : Column(
                  children: [
                    for (var i = 0; i < audit.length; i++) ...[
                      if (i > 0) const Divider(),
                      ListTile(
                        dense: true,
                        leading: const Icon(Icons.history_outlined),
                        title: Text(audit[i]['action'] as String? ?? ''),
                        subtitle: Text(
                          '${(audit[i]['actor'] as Map?)?['name'] ?? 'system'} · ${audit[i]['entityType']} · ${formatDateTime(DateTime.parse(audit[i]['createdAt'] as String))}',
                        ),
                      ),
                    ],
                    TextButton(onPressed: () => context.go('/admin/audit-log'), child: const Text('View full audit log')),
                  ],
                ),
        ),
      ],
    );
  }
}

// ---------------------------------------------------------------- shared pieces

class _StoreStats extends StatelessWidget {
  final Map<String, dynamic> data;
  const _StoreStats({required this.data});

  @override
  Widget build(BuildContext context) {
    final today = Map<String, dynamic>.from(data['today'] as Map? ?? {});
    final low = (data['lowStockCount'] ?? 0) as num;
    final out = (data['outOfStockCount'] ?? 0) as num;
    final pending = (data['pendingOrders'] ?? 0) as num;
    final disc = (data['openDiscrepancies'] ?? 0) as num;
    return _StatGrid(tiles: [
      _StatTile(label: "Today's revenue", value: formatCurrency(today['totalRevenue'] ?? 0), icon: Icons.payments_outlined, accent: AppColors.success),
      _StatTile(label: 'POS sales today', value: '${today['posSalesCount'] ?? 0}', icon: Icons.point_of_sale),
      _StatTile(label: 'Items sold today', value: '${today['totalItemsSold'] ?? 0}', icon: Icons.shopping_bag_outlined),
      _StatTile(label: 'Open orders', value: '$pending', icon: Icons.shopping_bag_outlined, accent: pending > 0 ? AppColors.primaryOrange : null, route: '/admin/orders'),
      _StatTile(label: 'Receipts to verify', value: '${data['paymentsToReview'] ?? 0}', icon: Icons.receipt_long_outlined, accent: ((data['paymentsToReview'] ?? 0) as num) > 0 ? AppColors.accentRed : null, route: '/admin/payments'),
      _StatTile(label: 'Low stock', value: '$low', icon: Icons.warning_amber_outlined, accent: low > 0 ? AppColors.accentRed : null, route: '/inventory/low-stock'),
      _StatTile(label: 'Out of stock', value: '$out', icon: Icons.remove_shopping_cart_outlined, accent: out > 0 ? AppColors.accentRed : null, route: '/inventory/low-stock'),
      _StatTile(label: 'Open stock reports', value: '$disc', icon: Icons.flag_outlined, accent: disc > 0 ? AppColors.primaryOrange : null, route: '/inventory/discrepancies'),
      _StatTile(label: 'Unread alerts', value: '${data['unreadNotifications'] ?? 0}', icon: Icons.notifications_outlined, accent: (data['unreadNotifications'] ?? 0) > 0 ? AppColors.accentRed : null, route: '/notifications'),
    ]);
  }
}

class _CategoryBreakdown extends StatelessWidget {
  final Map<String, dynamic> data;
  const _CategoryBreakdown({required this.data});

  @override
  Widget build(BuildContext context) {
    final cats = (data['categoriesToday'] as List? ?? []).cast<Map<String, dynamic>>();
    final max = cats.isEmpty ? 1.0 : (cats.first['revenue'] as num).toDouble().clamp(1, double.infinity);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const _SectionTitle("Today's revenue by category"),
        const SizedBox(height: 8),
        Card(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: cats.isEmpty
                ? const Text('No sales yet today')
                : Column(
                    children: [
                      for (final c in cats)
                        Padding(
                          padding: const EdgeInsets.symmetric(vertical: 6),
                          child: Row(
                            children: [
                              SizedBox(width: 130, child: Text(ProductCategory.label(c['category'] as String))),
                              Expanded(
                                child: LinearProgressIndicator(
                                  value: (c['revenue'] as num) / max,
                                  minHeight: 8,
                                  borderRadius: BorderRadius.circular(4),
                                ),
                              ),
                              const SizedBox(width: 12),
                              Text(formatCurrency(c['revenue'] as num), style: const TextStyle(fontWeight: FontWeight.w600)),
                            ],
                          ),
                        ),
                    ],
                  ),
          ),
        ),
      ],
    );
  }
}

class _ShiftCard extends StatelessWidget {
  final Map<String, dynamic>? shift;
  const _ShiftCard({required this.shift});

  @override
  Widget build(BuildContext context) {
    final open = shift != null;
    final s = open ? Map<String, dynamic>.from(shift!['shift'] as Map) : null;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Row(
          children: [
            Icon(Icons.schedule_outlined, color: open ? AppColors.success : AppColors.textSecondary, size: 32),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(open ? 'Shift open' : 'No shift open', style: Theme.of(context).textTheme.titleMedium),
                  Text(
                    open
                        ? 'Since ${formatDateTime(DateTime.parse(s!['openedAt'] as String))} · ${shift!['salesCount']} sale(s) · cash expected ${formatCurrency(shift!['closingCashExpected'] ?? 0)}'
                        : 'Open a shift with your starting cash so today\'s sales are tied to your drawer.',
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                ],
              ),
            ),
            const SizedBox(width: 8),
            open
                ? OutlinedButton(onPressed: () => context.go('/shift'), child: const Text('Close shift'))
                : ElevatedButton(onPressed: () => context.go('/shift'), child: const Text('Open shift')),
          ],
        ),
      ),
    );
  }
}

class _StatGrid extends StatelessWidget {
  final List<_StatTile> tiles;
  const _StatGrid({required this.tiles});

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final columns = (constraints.maxWidth / 200).floor().clamp(1, 4);
        return GridView.count(
          crossAxisCount: columns,
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          crossAxisSpacing: 12,
          mainAxisSpacing: 12,
          childAspectRatio: 1.9,
          children: tiles,
        );
      },
    );
  }
}

class _StatTile extends StatelessWidget {
  final String label;
  final String value;
  final IconData icon;
  final Color? accent;
  final String? route;
  const _StatTile({required this.label, required this.value, required this.icon, this.accent, this.route});

  @override
  Widget build(BuildContext context) {
    final color = accent ?? AppColors.textSecondary;
    return Card(
      child: InkWell(
        onTap: route == null ? null : () => context.go(route!),
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Row(
            children: [
              Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(color: AppColors.tint(color), borderRadius: BorderRadius.circular(10)),
                child: Icon(icon, color: color, size: 22),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(value, style: Theme.of(context).textTheme.titleLarge, maxLines: 1, overflow: TextOverflow.ellipsis),
                    Text(label, style: Theme.of(context).textTheme.bodySmall, maxLines: 1, overflow: TextOverflow.ellipsis),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _SectionTitle extends StatelessWidget {
  final String text;
  const _SectionTitle(this.text);
  @override
  Widget build(BuildContext context) => Text(text, style: Theme.of(context).textTheme.titleMedium);
}

class _Action {
  final String label;
  final IconData icon;
  final String route;
  final bool primary;
  const _Action(this.label, this.icon, this.route, {this.primary = false});
}

class _QuickActions extends StatelessWidget {
  final List<_Action> actions;
  const _QuickActions({required this.actions});

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: [
        for (final a in actions)
          a.primary
              ? ElevatedButton.icon(onPressed: () => context.go(a.route), icon: Icon(a.icon, size: 18), label: Text(a.label))
              : OutlinedButton.icon(onPressed: () => context.go(a.route), icon: Icon(a.icon, size: 18), label: Text(a.label)),
      ],
    );
  }
}
