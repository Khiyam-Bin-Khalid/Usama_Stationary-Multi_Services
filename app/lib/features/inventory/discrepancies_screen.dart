import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../core/format.dart';
import '../../core/providers.dart';
import '../../core/roles.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/status_style.dart';
import '../../data/models/discrepancy.dart';

final _discrepanciesProvider = FutureProvider.autoDispose.family<List<DiscrepancyReport>, String>(
  (ref, status) => ref.watch(discrepancyApiProvider).list(status: status),
);

/// Spec §3.3: staff flag "shelf count doesn't match system"; Admin / Super
/// Admin resolve it (optionally applying the shelf count as an adjustment).
class DiscrepanciesScreen extends ConsumerStatefulWidget {
  const DiscrepanciesScreen({super.key});

  @override
  ConsumerState<DiscrepanciesScreen> createState() => _DiscrepanciesScreenState();
}

class _DiscrepanciesScreenState extends ConsumerState<DiscrepanciesScreen> {
  String _status = 'open';

  @override
  Widget build(BuildContext context) {
    final role = ref.watch(authStateProvider).valueOrNull?.role ?? UserRole.staff;
    final canResolve = Permissions.resolveDiscrepancies(role);
    final listAsync = ref.watch(_discrepanciesProvider(_status));

    return Scaffold(
      floatingActionButton: canResolve
          ? null
          : FloatingActionButton.extended(
              onPressed: () => context.go('/inventory'),
              icon: const Icon(Icons.flag_outlined),
              label: const Text('Report from stock list'),
            ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(12),
            child: Row(
              children: [
                for (final s in const ['open', 'resolved', 'dismissed']) ...[
                  ChoiceChip(
                    label: Text(s[0].toUpperCase() + s.substring(1)),
                    selected: _status == s,
                    onSelected: (_) => setState(() => _status = s),
                  ),
                  const SizedBox(width: 6),
                ],
                const Spacer(),
                IconButton(icon: const Icon(Icons.refresh), onPressed: () => ref.invalidate(_discrepanciesProvider)),
              ],
            ),
          ),
          Expanded(
            child: listAsync.when(
              loading: () => const Center(child: CircularProgressIndicator()),
              error: (e, _) => Center(child: Text('Failed to load: $e')),
              data: (reports) {
                if (reports.isEmpty) return Center(child: Text('No $_status reports'));
                return ListView.separated(
                  itemCount: reports.length,
                  separatorBuilder: (_, __) => const Divider(),
                  itemBuilder: (context, i) {
                    final r = reports[i];
                    final diff = r.difference;
                    return ListTile(
                      leading: const Icon(Icons.flag_outlined, color: AppColors.primaryOrange),
                      title: Text('${r.productName} · ${ProductCategory.label(r.category)}'),
                      subtitle: Text(
                        'System ${r.systemQty} · Counted ${r.countedQty} · Reported by ${r.reportedByName ?? '—'} on ${formatDateTime(r.createdAt)}'
                        '${r.note != null && r.note!.isNotEmpty ? '\n"${r.note}"' : ''}'
                        '${r.resolution != null && r.resolution!.isNotEmpty ? '\nResolution: ${r.resolution}' : ''}',
                      ),
                      isThreeLine: true,
                      trailing: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          StatusBadge(
                            label: diff == 0 ? 'Match' : (diff > 0 ? '+$diff' : '$diff'),
                            tone: diff == 0 ? StatusTone.success : StatusTone.danger,
                          ),
                          if (canResolve && r.isOpen)
                            PopupMenuButton<String>(
                              onSelected: (choice) => _resolve(r, choice),
                              itemBuilder: (_) => const [
                                PopupMenuItem(value: 'apply', child: Text('Apply shelf count to stock')),
                                PopupMenuItem(value: 'resolve', child: Text('Mark resolved (no stock change)')),
                                PopupMenuItem(value: 'dismiss', child: Text('Dismiss', style: TextStyle(color: AppColors.accentRed))),
                              ],
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
      ),
    );
  }

  Future<void> _resolve(DiscrepancyReport r, String choice) async {
    final controller = TextEditingController();
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(choice == 'apply'
            ? 'Set ${r.productName} stock to ${r.countedQty}?'
            : choice == 'dismiss'
                ? 'Dismiss this report?'
                : 'Mark as resolved?'),
        content: TextField(controller: controller, decoration: const InputDecoration(labelText: 'Resolution note (optional)')),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Confirm')),
        ],
      ),
    );
    if (ok != true) return;
    try {
      await ref.read(discrepancyApiProvider).resolve(
            r.id,
            applyAdjustment: choice == 'apply',
            dismiss: choice == 'dismiss',
            resolution: controller.text,
          );
      ref.invalidate(_discrepanciesProvider);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Report updated'), backgroundColor: AppColors.success),
        );
      }
    } catch (e) {
      final message = e.toString();
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message), backgroundColor: AppColors.accentRed));
    }
  }
}
