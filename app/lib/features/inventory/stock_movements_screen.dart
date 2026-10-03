import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../core/format.dart';
import '../../core/providers.dart';
import '../../core/roles.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/status_style.dart';
import '../../data/models/inventory_movement.dart';
import '../../widgets/product_image.dart';

class _MovementFilter {
  final String? productId;
  final String? category;
  final String? type;
  final DateTime? from;
  final DateTime? to;
  const _MovementFilter({this.productId, this.category, this.type, this.from, this.to});

  @override
  bool operator ==(Object other) =>
      other is _MovementFilter && other.productId == productId && other.category == category && other.type == type && other.from == from && other.to == to;
  @override
  int get hashCode => Object.hash(productId, category, type, from, to);
}

final _movementsProvider = FutureProvider.autoDispose.family<List<InventoryMovement>, _MovementFilter>(
  (ref, f) => ref.watch(inventoryApiProvider).movements(productId: f.productId, category: f.category, type: f.type, from: f.from, to: f.to),
);

const _types = {
  'sale': 'Sale',
  'purchase': 'Purchase / stock in',
  'adjustment': 'Adjustment',
  'return': 'Return / restock',
};

/// Stock-movement history: product (with image), SKU, previous stock,
/// change, resulting stock, movement type, related sale/order, who did it
/// and when. Filter by product (from the inventory row), category, type or
/// date range.
class StockMovementsScreen extends ConsumerStatefulWidget {
  final String? productId;
  const StockMovementsScreen({super.key, this.productId});

  @override
  ConsumerState<StockMovementsScreen> createState() => _StockMovementsScreenState();
}

class _StockMovementsScreenState extends ConsumerState<StockMovementsScreen> {
  String? _category;
  String? _type;
  DateTimeRange? _range;
  late String? _productId = widget.productId;

  @override
  void didUpdateWidget(covariant StockMovementsScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.productId != widget.productId) _productId = widget.productId;
  }

  _MovementFilter get _filter => _MovementFilter(
        productId: _productId,
        category: _category,
        type: _type,
        from: _range?.start,
        to: _range == null ? null : DateTime(_range!.end.year, _range!.end.month, _range!.end.day, 23, 59, 59),
      );

  Future<void> _pickRange() async {
    final now = DateTime.now();
    final picked = await showDateRangePicker(
      context: context,
      firstDate: DateTime(now.year - 3),
      lastDate: now,
      initialDateRange: _range,
    );
    if (picked != null) setState(() => _range = picked);
  }

  @override
  Widget build(BuildContext context) {
    final movementsAsync = ref.watch(_movementsProvider(_filter));

    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Text('Stock movements', style: Theme.of(context).textTheme.titleLarge),
                  const Spacer(),
                  IconButton(icon: const Icon(Icons.refresh), onPressed: () => ref.invalidate(_movementsProvider)),
                ],
              ),
              const SizedBox(height: 8),
              SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: Row(
                  children: [
                    if (_productId != null) ...[
                      InputChip(label: const Text('One product'), onDeleted: () => setState(() => _productId = null)),
                      const SizedBox(width: 6),
                    ],
                    ChoiceChip(label: const Text('All types'), selected: _type == null, onSelected: (_) => setState(() => _type = null)),
                    const SizedBox(width: 6),
                    for (final e in _types.entries) ...[
                      ChoiceChip(label: Text(e.value), selected: _type == e.key, onSelected: (_) => setState(() => _type = e.key)),
                      const SizedBox(width: 6),
                    ],
                    const SizedBox(width: 12),
                    DropdownButton<String?>(
                      value: _category,
                      hint: const Text('Category'),
                      items: [
                        const DropdownMenuItem<String?>(value: null, child: Text('All categories')),
                        for (final c in ProductCategory.all) DropdownMenuItem<String?>(value: c, child: Text(ProductCategory.label(c))),
                      ],
                      onChanged: (v) => setState(() => _category = v),
                    ),
                    const SizedBox(width: 12),
                    OutlinedButton.icon(
                      onPressed: _pickRange,
                      icon: const Icon(Icons.date_range, size: 18),
                      label: Text(_range == null ? 'Date range' : '${formatPeriodLabel(_range!.start, 'daily')} – ${formatPeriodLabel(_range!.end, 'daily')}'),
                    ),
                    if (_range != null) IconButton(icon: const Icon(Icons.close, size: 18), onPressed: () => setState(() => _range = null)),
                  ],
                ),
              ),
            ],
          ),
        ),
        Expanded(
          child: movementsAsync.when(
            loading: () => const Center(child: CircularProgressIndicator()),
            error: (e, _) => Center(child: Text('Failed to load: $e')),
            data: (rows) {
              if (rows.isEmpty) return const Center(child: Text('No stock movements match these filters'));
              return ListView.separated(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
                itemCount: rows.length,
                separatorBuilder: (_, __) => const Divider(height: 1),
                itemBuilder: (context, i) => _MovementRow(row: rows[i]),
              );
            },
          ),
        ),
      ],
    );
  }
}

class _MovementRow extends StatelessWidget {
  final InventoryMovement row;
  const _MovementRow({required this.row});

  @override
  Widget build(BuildContext context) {
    final small = Theme.of(context).textTheme.bodySmall;
    final isIn = row.quantityDelta > 0;
    final tone = switch (row.type) {
      'sale' => StatusTone.info,
      'return' => StatusTone.success,
      'purchase' => StatusTone.success,
      _ => StatusTone.warning,
    };
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 10),
      child: Row(
        children: [
          ProductImage(imageUrl: row.imageUrl, size: 44),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(row.productName, style: const TextStyle(fontWeight: FontWeight.w600)),
                Text('SKU ${row.sku ?? '—'} · ${formatDateTime(row.createdAt)}', style: small),
                Text(
                  [
                    if (row.reference != null && row.reference!.isNotEmpty) 'Ref ${row.reference}',
                    if (row.reason != null && row.reason!.isNotEmpty) row.reason!,
                    if (row.actorName != null) 'by ${row.actorName}${row.actorRole != null ? ' (${UserRole.label(row.actorRole!)})' : ''}',
                  ].join(' · '),
                  style: small,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),
          const SizedBox(width: 12),
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text(
                '${isIn ? '+' : ''}${row.quantityDelta}',
                style: TextStyle(fontWeight: FontWeight.w800, fontSize: 16, color: isIn ? AppColors.success : AppColors.accentRed),
              ),
              Text('${row.previousStock ?? '?'} → ${row.resultingStock}${row.unit != null ? ' ${row.unit}' : ''}', style: small),
              const SizedBox(height: 4),
              StatusBadge(label: _types[row.type] ?? row.type, tone: tone),
            ],
          ),
        ],
      ),
    );
  }
}
