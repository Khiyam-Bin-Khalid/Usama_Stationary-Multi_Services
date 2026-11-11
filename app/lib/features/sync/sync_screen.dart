import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../core/format.dart';
import '../../core/providers.dart';
import '../../core/roles.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/status_style.dart';
import '../../data/local/app_database.dart';
import '../../data/repositories/sync_service.dart';

final _queuedSalesProvider = StreamProvider.autoDispose<List<QueuedSale>>((ref) {
  return ref.watch(appDatabaseProvider)?.watchUnsyncedSales() ?? Stream.value(const []);
});

final _queuedOpsProvider = StreamProvider.autoDispose<List<PendingOp>>((ref) {
  return ref.watch(appDatabaseProvider)?.watchPendingOps() ?? Stream.value(const []);
});

/// Everything saved on this device that the server doesn't have yet, and why.
/// A change the server rejected waits here for an Admin to retry or discard:
/// it's never dropped silently, because it may be a real sale.
class SyncScreen extends ConsumerWidget {
  const SyncScreen({super.key});

  Future<void> _syncNow(WidgetRef ref) async => ref.read(syncServiceProvider)?.syncNow(retryFailedPhotos: true);

  void _report(BuildContext context, Object error) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(error is StateError ? error.message : '$error'), backgroundColor: AppColors.accentRed),
    );
  }

  Future<bool> _confirmDiscard(BuildContext context, String what) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Discard this change?'),
        content: Text('$what will be removed from this device and will never reach the server.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Keep')),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: AppColors.accentRed),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Discard'),
          ),
        ],
      ),
    );
    return ok == true;
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final db = ref.watch(appDatabaseProvider);
    final service = ref.watch(syncServiceProvider);
    final role = ref.watch(authStateProvider).valueOrNull?.role ?? UserRole.staff;
    final isAdmin = Permissions.editInventory(role);
    final status = ref.watch(syncStatusProvider).valueOrNull ?? service?.status;
    final sales = ref.watch(_queuedSalesProvider).valueOrNull ?? const [];
    final ops = ref.watch(_queuedOpsProvider).valueOrNull ?? const [];

    if (db == null) return const Center(child: Text('The web app works online only, so nothing is queued here.'));

    final retry = status == SyncStatus.syncing ? null : () => _syncNow(ref);
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Row(
          children: [
            Expanded(
              child: Text(
                sales.isEmpty && ops.isEmpty ? 'Everything on this device has reached the server.' : '${sales.length + ops.length} item(s) waiting to sync',
                style: Theme.of(context).textTheme.titleMedium,
              ),
            ),
            FilledButton.icon(onPressed: retry, icon: const Icon(Icons.sync), label: const Text('Sync now')),
          ],
        ),
        const SizedBox(height: 12),
        if (ops.isNotEmpty) ...[
          Text('Product changes', style: Theme.of(context).textTheme.titleSmall),
          Card(
            child: Column(
              children: [
                for (final op in ops)
                  _QueueRow(
                    title: op.label,
                    subtitle: formatDateTime(op.createdAt),
                    error: op.lastError,
                    blocked: op.type != 'product_create' && isLocalProductId(op.productId ?? ''),
                    canResolve: isAdmin,
                    onRetry: () async {
                      await db.retryOp(op.seq);
                      await _syncNow(ref);
                    },
                    onDiscard: () async {
                      if (!await _confirmDiscard(context, op.label)) return;
                      try {
                        await db.discardOp(op);
                      } catch (e) {
                        if (context.mounted) _report(context, e);
                      }
                    },
                  ),
              ],
            ),
          ),
          const SizedBox(height: 12),
        ],
        if (sales.isNotEmpty) ...[
          Text('Sales', style: Theme.of(context).textTheme.titleSmall),
          Card(
            child: Column(
              children: [
                for (final sale in sales)
                  _QueueRow(
                    title: '${formatCurrency(sale.total)} · ${sale.items.map((i) => i['name'] ?? 'Item').join(', ')}',
                    subtitle: '${formatDateTime(sale.createdAt)}${sale.cashierName != null ? ' · ${sale.cashierName}' : ''}',
                    error: sale.syncError,
                    blocked: sale.waitsForProduct,
                    canResolve: isAdmin,
                    onRetry: () async {
                      await db.retrySale(sale.clientTxnId);
                      await _syncNow(ref);
                    },
                    onDiscard: () async {
                      if (await _confirmDiscard(context, 'This ${formatCurrency(sale.total)} sale')) await db.discardSale(sale);
                    },
                  ),
              ],
            ),
          ),
        ],
      ],
    );
  }
}

class _QueueRow extends StatelessWidget {
  final String title;
  final String subtitle;
  final String? error;
  final bool blocked;
  final bool canResolve;
  final VoidCallback onRetry;
  final VoidCallback onDiscard;

  const _QueueRow({
    required this.title,
    required this.subtitle,
    required this.error,
    required this.blocked,
    required this.canResolve,
    required this.onRetry,
    required this.onDiscard,
  });

  @override
  Widget build(BuildContext context) {
    final failed = error != null;
    return ListTile(
      title: Text(title, maxLines: 2, overflow: TextOverflow.ellipsis),
      subtitle: Text(failed ? '$subtitle\n$error' : subtitle, style: failed ? const TextStyle(color: AppColors.accentRed) : null),
      isThreeLine: failed,
      trailing: failed
          ? (canResolve
              ? Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    IconButton(icon: const Icon(Icons.refresh), tooltip: 'Retry', onPressed: onRetry),
                    IconButton(icon: const Icon(Icons.delete_outline, color: AppColors.accentRed), tooltip: 'Discard', onPressed: onDiscard),
                  ],
                )
              : const StatusBadge(label: 'Needs an Admin', tone: StatusTone.danger))
          : StatusBadge(label: blocked ? 'Waiting for product' : 'Waiting', tone: StatusTone.warning),
    );
  }
}
