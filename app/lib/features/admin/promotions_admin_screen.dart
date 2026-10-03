import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../core/format.dart';
import '../../core/providers.dart';
import '../../core/roles.dart';
import '../../data/models/promotion.dart';

final _promotionsProvider = FutureProvider.autoDispose<List<Promotion>>((ref) => ref.watch(promotionApiProvider).allForAdmin());

class PromotionsAdminScreen extends ConsumerWidget {
  const PromotionsAdminScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final promotionsAsync = ref.watch(_promotionsProvider);

    return Scaffold(
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _showForm(context, ref),
        icon: const Icon(Icons.add),
        label: const Text('New deal'),
      ),
      body: promotionsAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(child: Text('Failed to load: $e')),
        data: (promotions) {
          if (promotions.isEmpty) return const Center(child: Text('No promotions yet'));
          final now = DateTime.now();
          return ListView.separated(
            itemCount: promotions.length,
            separatorBuilder: (_, __) => const Divider(height: 1),
            itemBuilder: (context, i) {
              final p = promotions[i];
              final active = now.isAfter(p.startDate) && now.isBefore(p.endDate);
              return ListTile(
                title: Text(p.name),
                subtitle: Text(
                    '${p.discountLabel} · ${formatDateTime(p.startDate)} → ${formatDateTime(p.endDate)} · ${p.categories.join(', ')}'),
                trailing: Icon(active ? Icons.check_circle : Icons.schedule, color: active ? Colors.green : null),
              );
            },
          );
        },
      ),
    );
  }

  void _showForm(BuildContext context, WidgetRef ref) {
    final nameController = TextEditingController();
    final valueController = TextEditingController();
    String discountType = 'percent';
    final categories = <String>{};
    DateTime start = DateTime.now();
    DateTime end = DateTime.now().add(const Duration(days: 30));

    showDialog(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (dialogContext, setDialogState) => AlertDialog(
          title: const Text('New seasonal deal'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(controller: nameController, decoration: const InputDecoration(labelText: 'Name (e.g. Special Summer Deal)')),
                Row(
                  children: [
                    Expanded(
                      child: DropdownButtonFormField<String>(
                        initialValue: discountType,
                        decoration: const InputDecoration(labelText: 'Type'),
                        items: const [
                          DropdownMenuItem(value: 'percent', child: Text('% off')),
                          DropdownMenuItem(value: 'flat', child: Text('Flat off')),
                        ],
                        onChanged: (v) => setDialogState(() => discountType = v!),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: TextField(
                          controller: valueController,
                          keyboardType: TextInputType.number,
                          decoration: const InputDecoration(labelText: 'Value')),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                Wrap(
                  spacing: 6,
                  children: [
                    for (final c in ProductCategory.all)
                      FilterChip(
                        label: Text(ProductCategory.label(c)),
                        selected: categories.contains(c),
                        onSelected: (v) => setDialogState(() => v ? categories.add(c) : categories.remove(c)),
                      ),
                  ],
                ),
              ],
            ),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(dialogContext), child: const Text('Cancel')),
            FilledButton(
              onPressed: () async {
                try {
                  await ref.read(promotionApiProvider).create({
                    'name': nameController.text,
                    'discountType': discountType,
                    'discountValue': double.tryParse(valueController.text) ?? 0,
                    'categories': categories.toList(),
                    'startDate': start.toIso8601String(),
                    'endDate': end.toIso8601String(),
                  });
                  if (dialogContext.mounted) Navigator.pop(dialogContext);
                  ref.invalidate(_promotionsProvider);
                } catch (e) {
                  final message = e.toString();
                  if (dialogContext.mounted) ScaffoldMessenger.of(dialogContext).showSnackBar(SnackBar(content: Text(message)));
                }
              },
              child: const Text('Create'),
            ),
          ],
        ),
      ),
    );
  }
}
