import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:image_picker/image_picker.dart';
import '../../core/format.dart';
import '../../core/providers.dart';
import '../../core/roles.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/status_style.dart';
import '../../data/models/product.dart';
import '../../widgets/product_image.dart';

final _inventoryListProvider = FutureProvider.autoDispose<List<Product>>(
  (ref) => ref.watch(productApiProvider).list(),
);

/// Spec §2: Admin / Super Admin add, edit, delete products and adjust stock.
/// Staff get a read-only view and can *report* a discrepancy instead.
///
/// Every row shows the product image, name, SKU (auto-generated), barcode
/// where set, price, current stock, reorder level and stock status.
/// [initialFilter] = 'low' opens the Low-stock view straight away.
class InventoryScreen extends ConsumerStatefulWidget {
  final String initialFilter;
  const InventoryScreen({super.key, this.initialFilter = 'all'});

  @override
  ConsumerState<InventoryScreen> createState() => _InventoryScreenState();
}

class _InventoryScreenState extends ConsumerState<InventoryScreen> {
  late String _filter = widget.initialFilter; // all | low | out
  String _search = '';
  String? _category;

  @override
  void didUpdateWidget(covariant InventoryScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.initialFilter != widget.initialFilter) _filter = widget.initialFilter;
  }

  void _toast(String message, {bool error = false}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: error ? AppColors.accentRed : AppColors.success,
      ),
    );
  }

  // ApiException.toString() appends the server's per-field validation
  // reasons (e.g. `"sku" is not allowed to be empty`) — using only
  // `.message` used to hide those and just say "Validation failed".
  String _errorText(Object e) => e.toString();

  @override
  Widget build(BuildContext context) {
    final role =
        ref.watch(authStateProvider).valueOrNull?.role ?? UserRole.staff;
    final canEdit = Permissions.editInventory(role);
    final productsAsync = ref.watch(_inventoryListProvider);

    return Scaffold(
      floatingActionButton: canEdit
          ? FloatingActionButton.extended(
              onPressed: () => _showProductForm(context),
              icon: const Icon(Icons.add),
              label: const Text('Add Product'),
            )
          : null,
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(12),
            child: Column(
              children: [
                TextField(
                  decoration: const InputDecoration(
                    hintText: 'Search by name, SKU or barcode (scan here)',
                    prefixIcon: Icon(Icons.qr_code_scanner_outlined),
                  ),
                  onChanged: (v) => setState(() => _search = v.trim().toLowerCase()),
                ),
                const SizedBox(height: 8),
                SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: Row(
                    children: [
                      ChoiceChip(
                        label: const Text('All'),
                        selected: _category == null,
                        onSelected: (_) => setState(() => _category = null),
                      ),
                      const SizedBox(width: 6),
                      for (final c in ProductCategory.all) ...[
                        ChoiceChip(
                          label: Text(ProductCategory.label(c)),
                          selected: _category == c,
                          onSelected: (_) => setState(() => _category = c),
                        ),
                        const SizedBox(width: 6),
                      ],
                      const SizedBox(width: 12),
                      FilterChip(
                        label: const Text('Low stock'),
                        selected: _filter == 'low',
                        onSelected: (v) =>
                            setState(() => _filter = v ? 'low' : 'all'),
                      ),
                      const SizedBox(width: 6),
                      FilterChip(
                        label: const Text('Out of stock'),
                        selected: _filter == 'out',
                        onSelected: (v) =>
                            setState(() => _filter = v ? 'out' : 'all'),
                      ),
                      const SizedBox(width: 6),
                      IconButton(
                        icon: const Icon(Icons.refresh),
                        onPressed: () => ref.invalidate(_inventoryListProvider),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          if (!canEdit)
            Container(
              width: double.infinity,
              color: AppColors.surface,
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              child: Row(
                children: [
                  const Icon(
                    Icons.info_outline,
                    size: 16,
                    color: AppColors.textSecondary,
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'Read-only. If the shelf count differs from the system, tap the flag to report it to an Admin.',
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                  ),
                ],
              ),
            ),
          Expanded(
            child: productsAsync.when(
              loading: () => const Center(child: CircularProgressIndicator()),
              error: (e, _) => Center(child: Text('Failed to load: $e')),
              data: (products) {
                final filtered = products.where((p) {
                  if (_category != null && p.category != _category)
                    return false;
                  if (_filter == 'low' && !p.isLowStock) return false;
                  if (_filter == 'out' && !p.isOutOfStock) return false;
                  if (_search.isNotEmpty &&
                      !p.name.toLowerCase().contains(_search) &&
                      !p.sku.toLowerCase().contains(_search) &&
                      !(p.barcode ?? '').toLowerCase().contains(_search)) {
                    return false;
                  }
                  return true;
                }).toList();
                if (filtered.isEmpty)
                  return const Center(child: Text('No products'));
                return ListView.separated(
                  padding: const EdgeInsets.only(bottom: 88),
                  itemCount: filtered.length,
                  separatorBuilder: (_, __) => const Divider(),
                  itemBuilder: (context, i) {
                    final p = filtered[i];
                    return _ProductRow(
                      product: p,
                      canEdit: canEdit,
                      onAdjust: () => _showAdjustStockDialog(context, p),
                      onEdit: () => _showProductForm(context, existing: p),
                      onDelete: () => _confirmDelete(context, p),
                      onReport: () => _showReportDialog(context, p),
                      onHistory: () => context.go('/inventory/movements?product=${p.id}'),
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

  Future<void> _confirmDelete(BuildContext context, Product product) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('Delete ${product.name}?'),
        content: const Text(
          'The product is removed from sale and inventory lists. Past sales and reports keep referencing it.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: AppColors.accentRed),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (ok != true) return;
    try {
      await ref.read(productApiProvider).delete(product.id);
      ref.invalidate(_inventoryListProvider);
      _toast('${product.name} deleted');
    } catch (e) {
      _toast(_errorText(e), error: true);
    }
  }

  void _showReportDialog(BuildContext context, Product product) {
    final counted = TextEditingController(
      text: product.currentStock.toString(),
    );
    final note = TextEditingController();
    showDialog(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text('Report discrepancy — ${product.name}'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'System count: ${product.currentStock} ${product.unit}',
              style: Theme.of(context).textTheme.bodySmall,
            ),
            const SizedBox(height: 8),
            TextField(
              controller: counted,
              keyboardType: TextInputType.number,
              decoration: const InputDecoration(labelText: 'Shelf count'),
            ),
            const SizedBox(height: 8),
            TextField(
              controller: note,
              decoration: const InputDecoration(
                labelText: 'Note (e.g. "2 damaged")',
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () async {
              final qty = int.tryParse(counted.text);
              if (qty == null || qty < 0) return;
              try {
                await ref
                    .read(discrepancyApiProvider)
                    .report(
                      productId: product.id,
                      countedQty: qty,
                      note: note.text,
                    );
                if (dialogContext.mounted) Navigator.pop(dialogContext);
                _toast('Reported to Admin');
              } catch (e) {
                _toast(_errorText(e), error: true);
              }
            },
            child: const Text('Send report'),
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
              decoration: const InputDecoration(
                labelText: 'Change (e.g. 10 or -5)',
              ),
            ),
            const SizedBox(height: 8),
            TextField(
              controller: reasonController,
              decoration: const InputDecoration(labelText: 'Reason'),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () async {
              final delta = num.tryParse(controller.text);
              if (delta == null || delta == 0 || reasonController.text.isEmpty)
                return;
              try {
                await ref
                    .read(productApiProvider)
                    .adjustStock(
                      product.id,
                      delta: delta,
                      reason: reasonController.text,
                    );
                if (dialogContext.mounted) Navigator.pop(dialogContext);
                ref.invalidate(_inventoryListProvider);
                _toast('Stock updated');
              } catch (e) {
                _toast(_errorText(e), error: true);
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
    final barcodeController = TextEditingController(text: existing?.barcode);
    final descriptionController = TextEditingController(text: existing?.description);
    final priceController = TextEditingController(
      text: existing?.price.toString(),
    );
    final stockController = TextEditingController(
      text: existing?.currentStock.toString() ?? '0',
    );
    final thresholdController = TextEditingController(
      text: existing?.reorderThreshold.toString() ?? '5',
    );
    String category = existing?.category ?? ProductCategory.stationery;
    bool isMadeToOrder = existing?.isMadeToOrder ?? false;
    bool isAvailableOnline = existing?.isAvailableOnline ?? true;
    XFile? pickedImage;
    Uint8List? pickedImageBytes;
    bool saving = false;
    final formKey = GlobalKey<FormState>();

    showDialog(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (dialogContext, setDialogState) => AlertDialog(
          title: Text(existing == null ? 'Add Product' : 'Edit product'),
          content: SingleChildScrollView(
            child: Form(
              key: formKey,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Center(
                    child: GestureDetector(
                      onTap: () async {
                        final picker = ImagePicker();
                        final file = await picker.pickImage(
                          source: ImageSource.gallery,
                          imageQuality: 85,
                        );
                        if (file == null) return;
                        final bytes = await file.readAsBytes();
                        setDialogState(() {
                          pickedImage = file;
                          pickedImageBytes = bytes;
                        });
                      },
                      child: Stack(
                        alignment: Alignment.bottomRight,
                        children: [
                          ClipRRect(
                            borderRadius: BorderRadius.circular(12),
                            child: pickedImageBytes != null
                                ? Image.memory(
                                    pickedImageBytes!,
                                    width: 100,
                                    height: 100,
                                    fit: BoxFit.cover,
                                  )
                                : ProductImage(
                                    imageUrl: existing?.imageUrl,
                                    size: 100,
                                    radius: 12,
                                  ),
                          ),
                          Container(
                            margin: const EdgeInsets.all(4),
                            padding: const EdgeInsets.all(4),
                            decoration: const BoxDecoration(
                              color: AppColors.primaryOrange,
                              shape: BoxShape.circle,
                            ),
                            child: const Icon(
                              Icons.camera_alt_outlined,
                              size: 16,
                              color: Colors.white,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 12),
                  TextFormField(
                    controller: nameController,
                    decoration: const InputDecoration(labelText: 'Name'),
                    validator: (v) => (v == null || v.trim().isEmpty)
                        ? 'Name is required'
                        : null,
                  ),
                  const SizedBox(height: 8),
                  // SKU is generated by the system (e.g. STN-00001); the
                  // field is optional for importing legacy codes only.
                  TextFormField(
                    controller: skuController,
                    readOnly: existing != null,
                    decoration: InputDecoration(
                      labelText: existing == null ? 'SKU (optional — auto-generated if blank)' : 'SKU',
                      helperText: existing == null
                          ? 'Leave blank to generate the next code for the category'
                          : 'System identifier — cannot be changed',
                      prefixIcon: const Icon(Icons.tag),
                    ),
                  ),
                  const SizedBox(height: 8),
                  TextFormField(
                    controller: barcodeController,
                    decoration: const InputDecoration(
                      labelText: 'Barcode (optional)',
                      helperText: 'Type or scan the product barcode',
                      prefixIcon: Icon(Icons.qr_code_2_outlined),
                    ),
                  ),
                  const SizedBox(height: 8),
                  DropdownButtonFormField<String>(
                    initialValue: category,
                    decoration: const InputDecoration(labelText: 'Category'),
                    items: [
                      for (final c in ProductCategory.all)
                        DropdownMenuItem(
                          value: c,
                          child: Text(ProductCategory.label(c)),
                        ),
                    ],
                    onChanged: (v) => setDialogState(() => category = v!),
                  ),
                  const SizedBox(height: 8),
                  TextFormField(
                    controller: priceController,
                    keyboardType: TextInputType.number,
                    decoration: const InputDecoration(labelText: 'Price (Rs.)'),
                    validator: (v) {
                      final parsed = double.tryParse(v ?? '');
                      if (parsed == null) return 'Enter a valid price';
                      if (parsed < 0) return 'Price cannot be negative';
                      return null;
                    },
                  ),
                  const SizedBox(height: 8),
                  if (existing == null) ...[
                    TextFormField(
                      controller: stockController,
                      keyboardType: TextInputType.number,
                      decoration: const InputDecoration(
                        labelText: 'Initial stock',
                      ),
                      validator: (v) =>
                          (v != null && v.isNotEmpty && int.tryParse(v) == null)
                          ? 'Enter a whole number'
                          : null,
                    ),
                    const SizedBox(height: 8),
                  ],
                  TextFormField(
                    controller: descriptionController,
                    maxLines: 2,
                    decoration: const InputDecoration(labelText: 'Description (optional)'),
                  ),
                  const SizedBox(height: 8),
                  TextFormField(
                    controller: thresholdController,
                    keyboardType: TextInputType.number,
                    decoration: const InputDecoration(
                      labelText: 'Reorder level (low-stock threshold)',
                      helperText:
                          'Alerts Admin when stock falls to this level (default 5)',
                    ),
                    validator: (v) =>
                        (v != null && v.isNotEmpty && int.tryParse(v) == null)
                        ? 'Enter a whole number'
                        : null,
                  ),
                  SwitchListTile(
                    contentPadding: EdgeInsets.zero,
                    title: const Text('Made to order (printing/garment job)'),
                    value: isMadeToOrder,
                    onChanged: (v) => setDialogState(() => isMadeToOrder = v),
                  ),
                  SwitchListTile(
                    contentPadding: EdgeInsets.zero,
                    title: const Text('Available online'),
                    value: isAvailableOnline,
                    onChanged: (v) =>
                        setDialogState(() => isAvailableOnline = v),
                  ),
                ],
              ),
            ),
          ),
          actions: [
            TextButton(
              onPressed: saving ? null : () => Navigator.pop(dialogContext),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: saving
                  ? null
                  : () async {
                      if (!formKey.currentState!.validate()) return;
                      final payload = {
                        'name': nameController.text,
                        'category': category,
                        'price': double.tryParse(priceController.text) ?? 0,
                        'reorderThreshold':
                            int.tryParse(thresholdController.text) ?? 0,
                        'isMadeToOrder': isMadeToOrder,
                        'isAvailableOnline': isAvailableOnline,
                        'barcode': barcodeController.text.trim(),
                        'description': descriptionController.text.trim(),
                      };
                      setDialogState(() => saving = true);
                      try {
                        final Product product;
                        if (existing == null) {
                          product = await ref.read(productApiProvider).create({
                            ...payload,
                            if (skuController.text.trim().isNotEmpty)
                              'sku': skuController.text.trim(),
                            'currentStock':
                                int.tryParse(stockController.text) ?? 0,
                          });
                        } else {
                          product = await ref
                              .read(productApiProvider)
                              .update(existing.id, payload);
                        }
                        if (pickedImageBytes != null) {
                          await ref
                              .read(productApiProvider)
                              .uploadImage(
                                product.id,
                                pickedImageBytes!,
                                pickedImage!.name,
                              );
                        }
                        if (dialogContext.mounted) Navigator.pop(dialogContext);
                        ref.invalidate(_inventoryListProvider);
                        _toast(
                          existing == null
                              ? 'Product added · SKU ${product.sku}'
                              : 'Product saved',
                        );
                      } catch (e) {
                        setDialogState(() => saving = false);
                        _toast(_errorText(e), error: true);
                      }
                    },
              child: saving
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Text('Save'),
            ),
          ],
        ),
      ),
    );
  }
}

/// Stock badge per the color map: low/out → accentRed, in stock → success.
class _StockBadge extends StatelessWidget {
  final Product product;
  const _StockBadge({required this.product});

  @override
  Widget build(BuildContext context) {
    if (product.isMadeToOrder)
      return const StatusBadge(label: 'Made to order', tone: StatusTone.info);
    if (product.isOutOfStock)
      return const StatusBadge(label: 'Out of stock', tone: StatusTone.danger);
    if (product.isLowStock)
      return StatusBadge(
        label: 'Only ${product.currentStock} left',
        tone: StatusTone.danger,
      );
    return StatusBadge(
      label: '${product.currentStock} ${product.unit} · In stock',
      tone: StatusTone.success,
    );
  }
}

/// One inventory row: image · name · SKU · barcode · price · stock ·
/// reorder level · status, with the role-appropriate actions.
class _ProductRow extends StatelessWidget {
  final Product product;
  final bool canEdit;
  final VoidCallback onAdjust;
  final VoidCallback onEdit;
  final VoidCallback onDelete;
  final VoidCallback onReport;
  final VoidCallback onHistory;
  const _ProductRow({
    required this.product,
    required this.canEdit,
    required this.onAdjust,
    required this.onEdit,
    required this.onDelete,
    required this.onReport,
    required this.onHistory,
  });

  @override
  Widget build(BuildContext context) {
    final p = product;
    final wide = MediaQuery.sizeOf(context).width >= 1000;
    final small = Theme.of(context).textTheme.bodySmall;
    final stockText = p.isMadeToOrder ? 'Made to order' : '${p.currentStock} ${p.unit}';

    final identity = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(p.name, style: const TextStyle(fontWeight: FontWeight.w600)),
        Text(
          'SKU ${p.sku}${p.barcode != null && p.barcode!.isNotEmpty ? ' · Barcode ${p.barcode}' : ''}',
          style: small,
        ),
        Text(
          '${ProductCategory.label(p.category)} · ${formatCurrency(p.price)}'
          '${wide ? '' : ' · Stock $stockText · Reorder at ${p.reorderThreshold}'}'
          '${p.createdByName != null ? ' · Added by ${p.createdByName} (${UserRole.label(p.createdByRole ?? '')})' : ''}',
          style: small,
        ),
      ],
    );

    final actions = Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        IconButton(
          icon: const Icon(Icons.history),
          tooltip: 'Stock movements',
          onPressed: onHistory,
        ),
        if (canEdit) ...[
          IconButton(icon: const Icon(Icons.tune), tooltip: 'Adjust stock', onPressed: onAdjust),
          IconButton(icon: const Icon(Icons.edit_outlined), tooltip: 'Edit', onPressed: onEdit),
          IconButton(
            icon: const Icon(Icons.delete_outline, color: AppColors.accentRed),
            tooltip: 'Delete',
            onPressed: onDelete,
          ),
        ] else
          IconButton(
            icon: const Icon(Icons.flag_outlined, color: AppColors.primaryOrange),
            tooltip: 'Report discrepancy',
            onPressed: onReport,
          ),
      ],
    );

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      child: Row(
        children: [
          ProductImage(imageUrl: p.imageUrl, size: 52),
          const SizedBox(width: 12),
          Expanded(child: identity),
          if (wide) ...[
            SizedBox(
              width: 120,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Text(stockText, style: const TextStyle(fontWeight: FontWeight.w600)),
                  Text('Reorder at ${p.reorderThreshold}', style: small),
                ],
              ),
            ),
            const SizedBox(width: 12),
          ],
          _StockBadge(product: p),
          const SizedBox(width: 4),
          actions,
        ],
      ),
    );
  }
}
