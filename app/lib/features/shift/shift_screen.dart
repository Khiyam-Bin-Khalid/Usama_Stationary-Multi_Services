import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../core/format.dart';
import '../../core/providers.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/status_style.dart';
import '../../data/models/shift.dart';

final _shiftHistoryProvider = FutureProvider.autoDispose<List<Shift>>((ref) => ref.watch(shiftApiProvider).list());

/// Spec §6: shift open/close with cash-drawer reconciliation (Z-report).
class ShiftScreen extends ConsumerWidget {
  const ShiftScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final currentAsync = ref.watch(currentShiftProvider);
    final historyAsync = ref.watch(_shiftHistoryProvider);

    void refresh() {
      ref.invalidate(currentShiftProvider);
      ref.invalidate(_shiftHistoryProvider);
    }

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        currentAsync.when(
          loading: () => const Center(child: CircularProgressIndicator()),
          error: (e, _) => Text('Could not load shift: $e'),
          data: (report) => report == null
              ? _OpenShiftCard(onOpened: refresh)
              : _CurrentShiftCard(report: report, onClosed: refresh),
        ),
        const SizedBox(height: 24),
        Text('Shift history', style: Theme.of(context).textTheme.titleMedium),
        const SizedBox(height: 8),
        historyAsync.when(
          loading: () => const LinearProgressIndicator(),
          error: (e, _) => Text('Failed to load: $e'),
          data: (shifts) {
            final closed = shifts.where((s) => !s.isOpen).toList();
            if (closed.isEmpty) return const Text('No closed shifts yet');
            return Card(
              child: Column(
                children: [
                  for (var i = 0; i < closed.length; i++) ...[
                    if (i > 0) const Divider(),
                    _HistoryTile(shift: closed[i]),
                  ],
                ],
              ),
            );
          },
        ),
      ],
    );
  }
}

class _OpenShiftCard extends ConsumerWidget {
  final VoidCallback onOpened;
  const _OpenShiftCard({required this.onOpened});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('No shift open', style: Theme.of(context).textTheme.titleLarge),
            const SizedBox(height: 4),
            Text('Count the cash in the drawer and open your shift. Every sale you record will be tied to it.',
                style: Theme.of(context).textTheme.bodySmall),
            const SizedBox(height: 16),
            ElevatedButton.icon(
              onPressed: () => _openDialog(context, ref),
              icon: const Icon(Icons.play_arrow),
              label: const Text('Open shift'),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _openDialog(BuildContext context, WidgetRef ref) async {
    final cash = TextEditingController(text: '0');
    final note = TextEditingController();
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Open shift'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(controller: cash, keyboardType: TextInputType.number, decoration: const InputDecoration(labelText: 'Opening cash float (Rs.)')),
            const SizedBox(height: 8),
            TextField(controller: note, decoration: const InputDecoration(labelText: 'Note (optional)')),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Open')),
        ],
      ),
    );
    if (ok != true) return;
    try {
      await ref.read(shiftApiProvider).open(openingCash: double.tryParse(cash.text) ?? 0, note: note.text);
      onOpened();
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(e.toString()), backgroundColor: AppColors.accentRed),
        );
      }
    }
  }
}

class _CurrentShiftCard extends ConsumerWidget {
  final ShiftReport report;
  final VoidCallback onClosed;
  const _CurrentShiftCard({required this.report, required this.onClosed});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final s = report.shift;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Text('Shift open', style: Theme.of(context).textTheme.titleLarge),
                const SizedBox(width: 8),
                const StatusBadge(label: 'Live', tone: StatusTone.success),
                const Spacer(),
                IconButton(icon: const Icon(Icons.refresh), onPressed: () => ref.invalidate(currentShiftProvider)),
              ],
            ),
            Text('Opened ${formatDateTime(s.openedAt)}', style: Theme.of(context).textTheme.bodySmall),
            const SizedBox(height: 16),
            Wrap(
              spacing: 24,
              runSpacing: 12,
              children: [
                _Figure('Opening cash', formatCurrency(s.openingCash)),
                _Figure('Sales', '${report.salesCount}'),
                _Figure('Total sales', formatCurrency(report.salesTotal)),
                _Figure('Cash sales', formatCurrency(report.cashSalesTotal)),
                _Figure('Card sales', formatCurrency(report.cardSalesTotal)),
                _Figure('Cash expected in drawer', formatCurrency(report.closingCashExpected), emphasis: true),
              ],
            ),
            const SizedBox(height: 16),
            ElevatedButton.icon(
              onPressed: () => _closeDialog(context, ref),
              icon: const Icon(Icons.stop),
              label: const Text('Close shift'),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _closeDialog(BuildContext context, WidgetRef ref) async {
    final cash = TextEditingController();
    final note = TextEditingController();
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Close shift'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Expected cash: ${formatCurrency(report.closingCashExpected)}'),
            const SizedBox(height: 12),
            TextField(controller: cash, keyboardType: TextInputType.number, decoration: const InputDecoration(labelText: 'Counted cash (Rs.)')),
            const SizedBox(height: 8),
            TextField(controller: note, decoration: const InputDecoration(labelText: 'Note (optional)')),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Close shift')),
        ],
      ),
    );
    if (ok != true) return;
    final counted = double.tryParse(cash.text);
    if (counted == null) return;
    try {
      final closed = await ref.read(shiftApiProvider).close(closingCashActual: counted, note: note.text);
      onClosed();
      if (context.mounted) {
        final v = closed.cashVariance ?? 0;
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text(v == 0 ? 'Shift closed — drawer balanced' : 'Shift closed — variance ${formatCurrency(v)}'),
          backgroundColor: v == 0 ? AppColors.success : AppColors.accentRed,
        ));
      }
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(e.toString()), backgroundColor: AppColors.accentRed),
        );
      }
    }
  }
}

class _Figure extends StatelessWidget {
  final String label;
  final String value;
  final bool emphasis;
  const _Figure(this.label, this.value, {this.emphasis = false});

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: Theme.of(context).textTheme.bodySmall),
        Text(value,
            style: emphasis
                ? Theme.of(context).textTheme.titleLarge?.copyWith(color: AppColors.primaryOrange)
                : Theme.of(context).textTheme.titleMedium),
      ],
    );
  }
}

class _HistoryTile extends StatelessWidget {
  final Shift shift;
  const _HistoryTile({required this.shift});

  @override
  Widget build(BuildContext context) {
    final v = shift.cashVariance ?? 0;
    return ListTile(
      leading: const Icon(Icons.schedule_outlined),
      title: Text('${formatDateTime(shift.openedAt)}${shift.staffName != null ? ' · ${shift.staffName}' : ''}'),
      subtitle: Text(
        '${shift.salesCount} sale(s) · ${formatCurrency(shift.salesTotal)} · expected ${formatCurrency(shift.closingCashExpected ?? 0)} · counted ${formatCurrency(shift.closingCashActual ?? 0)}',
      ),
      trailing: StatusBadge(
        label: v == 0 ? 'Balanced' : 'Variance ${formatCurrency(v)}',
        tone: v == 0 ? StatusTone.success : StatusTone.danger,
      ),
    );
  }
}
