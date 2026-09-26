import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../core/format.dart';
import '../../core/providers.dart';
import '../../core/roles.dart';
import '../../core/theme/status_style.dart';
import '../../data/models/product.dart';
import '../../data/remote/api_client.dart';

final _inventoryListProvider = FutureProvider.autoDispose<List<Product>>((ref) => ref.watch(productApiProvider).list());

class InventoryScreen extends ConsumerStatefulWidget {
  const InventoryScreen({super.key});

  @override
  ConsumerState<InventoryScreen> createState() => _InventoryScreenState();
}

class _InventoryScreenState extends ConsumerState<InventoryScreen> {
  bool _lowStockOnly = false;

  @override
  Widget build(BuildContext context) {
    final role = ref.watch(authStateProvider).valueOrNull?.role ?? UserRole.staff;
    final canEdit = role == UserRole.admin || role == UserRole.superadmin;
    final productsAsync = ref.watch(_inventoryListProvider);

    return Scaffold(
      floatingActionButton: canEdit
          ? FloatingActionButton.extended(
              onPressed: () => _showProductForm(context),
              icon: const Icon(Icons.add),
              label: const Text('New product'),
            )
          : null,
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(12),
            child: Row(
              children: [
                FilterChip(
                  label: const Text('Low stock only'),
                  selected: _lowStockOnly,
                  onSelected: (v) => setState(() => _lowStockOnly = v),
                ),
                const Spacer(),
                IconButton(icon: const Icon(Icons.refresh), onPressed: () => ref.invalidate(_inventoryListProvider)),
              ],
            ),
          ),
          Expanded(
            child: productsAsync.when(
              loading: () => const Center(child: CircularProgressIndicator()),
              error: (e, _) => Center(child: Text('Failed to load: $e')),
              data: (products) {
                final filtered = _lowStockOnly ? products.where((p) => p.isLowStock).toList() : products;
                if (filtered.isEmpty) return const Center(child: Text('No products'));
                return ListView.separated(
                  itemCount: filtered.length,
                  separatorBuilder: (_, __) => const Divider(height: 1),
                  itemBuilder: (context, i) {
                    final p = filtered[i];
                    return ListTile(
                      title: Text(p.name),
                      subtitle: Text('${ProductCategory.label(p.category)} · SKU ${p.sku} · ${formatCurrency(p.price)}'),
                      trailing: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          if (p.isMadeToOrder)
                            const StatusBadge(label: 'Made to order', tone: StatusTone.info)
                          else if (p.isLowStock)
                            StatusBadge(label: 'Low: ${p.currentStock}', tone: StatusTone.warning)
                          else
                            Text('${p.currentStock} ${p.unit}'),
                          IconButton(
                            icon: const Icon(Icons.tune),
                            tooltip: 'Adjust stock',
                            onPressed: () => _showAdjustStockDialog(context, p),
                          ),
                          if (canEdit)
                            IconButton(
                              icon: const Icon(Icons.edit_outlined),
                              onPressed: () => _showProductForm(context, existing: p),
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

  void _showAdjustStockDialog(BuildContext context, Product product) {
    final controller = TextEditingController();
    final reasonController = TextEditingController();
    showDialog(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text('Adjust stock — ${product.name}'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: controller,
              keyboardType: const TextInputType.numberWithOptions(signed: true),
              decoration: const InputDecoration(labelText: 'Change (e.g. 10 or -5)'),
            ),
            const SizedBox(height: 8),
            TextField(controller: reasonController, decoration: const InputDecoration(labelText: 'Reason')),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(dialogContext), child: const Text('Cancel')),
          FilledButton(
            onPressed: () async {
              final delta = num.tryParse(controller.text);
              if (delta == null || delta == 0 || reasonController.text.isEmpty) return;
              try {
                await ref.read(productApiProvider).adjustStock(product.id, delta: delta, reason: reasonController.text);
                if (dialogContext.mounted) Navigator.pop(dialogContext);
                ref.invalidate(_inventoryListProvider);
              } catch (e) {
                final message = e is ApiException ? e.message : e.toString();
                if (dialogContext.mounted) {
                  ScaffoldMessenger.of(dialogContext).showSnackBar(SnackBar(content: Text(message)));
                }
              }
            },
            child: const Text('Save'),
          ),
        ],
      ),
    );
  }

  void _showProductForm(BuildContext context, {Product? existing}) {
    final nameController = TextEditingController(text: existing?.name);
    final skuController = TextEditingController(text: existing?.sku);
    final priceController = TextEditingController(text: existing?.price.toString());
    final stockController = TextEditingController(text: existing?.currentStock.toString() ?? '0');
    final thresholdController = TextEditingController(text: existing?.reorderThreshold.toString() ?? '5');
    String category = existing?.category ?? ProductCategory.stationery;
    bool isMadeToOrder = existing?.isMadeToOrder ?? false;
    bool isAvailableOnline = existing?.isAvailableOnline ?? true;

    showDialog(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (dialogContext, setDialogState) => AlertDialog(
          title: Text(existing == null ? 'New product' : 'Edit product'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(controller: nameController, decoration: const InputDecoration(labelText: 'Name')),
                if (existing == null) TextField(controller: skuController, decoration: const InputDecoration(labelText: 'SKU')),
                DropdownButtonFormField<String>(
                  initialValue: category,
                  decoration: const InputDecoration(labelText: 'Category'),
                  items: [for (final c in ProductCategory.all) DropdownMenuItem(value: c, child: Text(ProductCategory.label(c)))],
                  onChanged: (v) => setDialogState(() => category = v!),
                ),
                TextField(
                    controller: priceController,
                    keyboardType: TextInputType.number,
                    decoration: const InputDecoration(labelText: 'Price')),
                if (existing == null)
                  TextField(
                      controller: stockController,
                      keyboardType: TextInputType.number,
                      decoration: const InputDecoration(labelText: 'Initial stock')),
                TextField(
                    controller: thresholdController,
                    keyboardType: TextInputType.number,
                    decoration: const InputDecoration(labelText: 'Reorder threshold')),
                SwitchListTile(
                  title: const Text('Made to order (printing/garment job)'),
                  value: isMadeToOrder,
                  onChanged: (v) => setDialogState(() => isMadeToOrder = v),
                ),
                SwitchListTile(
                  title: const Text('Available online'),
                  value: isAvailableOnline,
                  onChanged: (v) => setDialogState(() => isAvailableOnline = v),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(dialogContext), child: const Text('Cancel')),
            FilledButton(
              onPressed: () async {
                final payload = {
                  'name': nameController.text,
                  'category': category,
                  'price': double.tryParse(priceController.text) ?? 0,
                  'reorderThreshold': int.tryParse(thresholdController.text) ?? 0,
                  'isMadeToOrder': isMadeToOrder,
                  'isAvailableOnline': isAvailableOnline,
                };
                try {
                  if (existing == null) {
                    await ref.read(productApiProvider).create({
                      ...payload,
                      'sku': skuController.text,
                      'currentStock': int.tryParse(stockController.text) ?? 0,
                    });
                  } else {
                    await ref.read(productApiProvider).update(existing.id, payload);
                  }
                  if (dialogContext.mounted) Navigator.pop(dialogContext);
                  ref.invalidate(_inventoryListProvider);
                } catch (e) {
                  final message = e is ApiException ? e.message : e.toString();
                  if (dialogContext.mounted) {
                    ScaffoldMessenger.of(dialogContext).showSnackBar(SnackBar(content: Text(message)));
                  }
                }
              },
              child: const Text('Save'),
            ),
          ],
        ),
      ),
    );
  }
}
