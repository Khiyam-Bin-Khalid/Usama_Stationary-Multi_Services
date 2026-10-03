import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../core/format.dart';
import '../../core/providers.dart';
import '../../core/theme/app_colors.dart';

final _auditProvider = FutureProvider.autoDispose.family<List<Map<String, dynamic>>, String>(
  (ref, action) => ref.watch(auditApiProvider).list(action: action),
);

/// Spec §3.1: Super Admin only — every create/update/delete with actor,
/// timestamp and before/after values.
class AuditLogScreen extends ConsumerStatefulWidget {
  const AuditLogScreen({super.key});

  @override
  ConsumerState<AuditLogScreen> createState() => _AuditLogScreenState();
}

class _AuditLogScreenState extends ConsumerState<AuditLogScreen> {
  String _filter = '';

  @override
  Widget build(BuildContext context) {
    final logsAsync = ref.watch(_auditProvider(_filter));
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.all(12),
          child: Row(
            children: [
              Expanded(
                child: TextField(
                  decoration: const InputDecoration(
                    hintText: 'Filter by action, e.g. user. / inventory. / auth.',
                    prefixIcon: Icon(Icons.filter_list),
                  ),
                  onSubmitted: (v) => setState(() => _filter = v.trim()),
                ),
              ),
              const SizedBox(width: 8),
              IconButton(icon: const Icon(Icons.refresh), onPressed: () => ref.invalidate(_auditProvider)),
            ],
          ),
        ),
        Expanded(
          child: logsAsync.when(
            loading: () => const Center(child: CircularProgressIndicator()),
            error: (e, _) => Center(child: Text('Failed to load: $e')),
            data: (logs) {
              if (logs.isEmpty) return const Center(child: Text('No audit entries'));
              return ListView.separated(
                itemCount: logs.length,
                separatorBuilder: (_, __) => const Divider(),
                itemBuilder: (context, i) => _AuditTile(entry: logs[i]),
              );
            },
          ),
        ),
      ],
    );
  }
}

class _AuditTile extends StatelessWidget {
  final Map<String, dynamic> entry;
  const _AuditTile({required this.entry});

  @override
  Widget build(BuildContext context) {
    final actor = entry['actor'] as Map?;
    final action = entry['action'] as String? ?? '';
    final isSecurity = action.startsWith('auth.') || action.contains('delete');
    final before = entry['before'];
    final after = entry['after'];
    final details = entry['details'];
    const mono = TextStyle(fontFamily: 'monospace', fontSize: 12, color: AppColors.textPrimary);

    return ExpansionTile(
      leading: Icon(isSecurity ? Icons.security_outlined : Icons.history_outlined,
          color: isSecurity ? AppColors.accentRed : AppColors.textSecondary),
      title: Text(action, style: const TextStyle(fontWeight: FontWeight.w600)),
      subtitle: Text(
        '${actor?['name'] ?? 'system'}${entry['actorRole'] != null ? ' (${entry['actorRole']})' : ''} · ${entry['entityType']} · ${formatDateTime(DateTime.parse(entry['createdAt'] as String))}',
      ),
      childrenPadding: const EdgeInsets.fromLTRB(56, 0, 16, 12),
      expandedCrossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (entry['entityId'] != null) Text('Entity: ${entry['entityId']}', style: Theme.of(context).textTheme.bodySmall),
        if (before != null) ...[const SizedBox(height: 6), const Text('Before', style: TextStyle(fontWeight: FontWeight.w600)), Text(jsonEncode(before), style: mono)],
        if (after != null) ...[const SizedBox(height: 6), const Text('After', style: TextStyle(fontWeight: FontWeight.w600)), Text(jsonEncode(after), style: mono)],
        if (details != null) ...[const SizedBox(height: 6), const Text('Details', style: TextStyle(fontWeight: FontWeight.w600)), Text(jsonEncode(details), style: mono)],
      ],
    );
  }
}
