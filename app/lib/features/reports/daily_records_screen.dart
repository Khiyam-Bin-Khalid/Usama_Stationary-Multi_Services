import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../core/format.dart';
import '../../core/roles.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/status_style.dart';
import '../../data/local/app_database.dart';
import '../../data/models/sale.dart';
import 'records_providers.dart';

/// Admin / Super Admin records of the last month, in table form: revenue per
/// date (tap a date for every line sold that day) and a stock record showing
/// what sold, what remains and what has sold out. Built from the device's own
/// database, so everything here works offline.
class DailyRecordsScreen extends ConsumerWidget {
  const DailyRecordsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final salesAsync = ref.watch(recordSalesProvider);
    final productsAsync = ref.watch(recordProductsProvider);

    return DefaultTabController(
      length: 2,
      child: Column(
        children: [
          const Material(
            color: AppColors.surface,
            child: TabBar(tabs: [Tab(text: 'Daily sales'), Tab(text: 'Stock record')]),
          ),
          Expanded(
            child: salesAsync.when(
              loading: () => const Center(child: CircularProgressIndicator()),
              error: (e, _) => Center(child: Padding(padding: const EdgeInsets.all(24), child: Text('Could not load records: $e'))),
              data: (sales) => productsAsync.when(
                loading: () => const Center(child: CircularProgressIndicator()),
                error: (e, _) => Center(child: Padding(padding: const EdgeInsets.all(24), child: Text('Could not load products: $e'))),
                data: (products) => TabBarView(
                  children: [
                    _DailySalesTab(sales: sales),
                    _StockRecordTab(rowsFor: (period) => buildStockRecord(sales.where(period.includes), products)),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Keeps wide tables usable on a phone: scrolls sideways instead of clipping.
class _WideTable extends StatelessWidget {
  final DataTable table;
  const _WideTable(this.table);

  @override
  Widget build(BuildContext context) {
    return Card(
      child: SingleChildScrollView(scrollDirection: Axis.horizontal, child: table),
    );
  }
}

DataColumn _column(String label, {bool numeric = false}) => DataColumn(label: Text(label), numeric: numeric);

class _DailySalesTab extends StatelessWidget {
  final List<Sale> sales;
  const _DailySalesTab({required this.sales});

  @override
  Widget build(BuildContext context) {
    final rows = summariseByDay(sales);
    final revenue = rows.fold<double>(0, (sum, r) => sum + r.revenue);
    final items = rows.fold<double>(0, (sum, r) => sum + r.itemsSold);
    final today = rows.where((r) => isToday(r.day)).firstOrNull;

    return ListView(
      padding: const EdgeInsets.all(12),
      children: [
        Wrap(
          spacing: 12,
          runSpacing: 12,
          children: [
            _Figure(label: "Today's revenue", value: formatCurrency(today?.revenue ?? 0)),
            _Figure(label: 'Revenue, ${AppDatabase.recordDays} days', value: formatCurrency(revenue)),
            _Figure(label: 'Invoices, ${AppDatabase.recordDays} days', value: '${sales.length}'),
            _Figure(label: 'Items sold, ${AppDatabase.recordDays} days', value: formatQuantity(items)),
          ],
        ),
        const SizedBox(height: 12),
        if (rows.isEmpty)
          const Padding(padding: EdgeInsets.only(top: 40), child: Center(child: Text('No sales recorded in the last month')))
        else
          _WideTable(
            DataTable(
              showCheckboxColumn: false,
              columns: [
                _column('Date'),
                _column('Invoices', numeric: true),
                _column('Items sold', numeric: true),
                _column('Cash', numeric: true),
                _column('Card', numeric: true),
                _column('Revenue', numeric: true),
                _column('Not synced', numeric: true),
              ],
              rows: [
                for (final row in rows)
                  DataRow(
                    onSelectChanged: (_) => _showDay(context, row.day),
                    cells: [
                      DataCell(Text(formatFullDay(row.day), style: const TextStyle(fontWeight: FontWeight.w600))),
                      DataCell(Text('${row.invoices}')),
                      DataCell(Text(formatQuantity(row.itemsSold))),
                      DataCell(Text(formatCurrency(row.cash))),
                      DataCell(Text(formatCurrency(row.card))),
                      DataCell(Text(formatCurrency(row.revenue), style: const TextStyle(fontWeight: FontWeight.w700))),
                      DataCell(Text(row.notSynced == 0 ? '—' : '${row.notSynced}')),
                    ],
                  ),
              ],
            ),
          ),
        const SizedBox(height: 8),
        Text('Tap a date to see every item sold that day.', style: Theme.of(context).textTheme.bodySmall),
      ],
    );
  }

  void _showDay(BuildContext context, DateTime day) {
    final daySales = sales.where((s) => dayOf(s.createdAt) == day).toList()..sort((a, b) => b.createdAt.compareTo(a.createdAt));
    showDialog<void>(
      context: context,
      builder: (ctx) => Dialog(
        insetPadding: const EdgeInsets.all(16),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(child: Text('Sales on ${formatFullDay(day)}', style: Theme.of(ctx).textTheme.titleMedium)),
                  IconButton(icon: const Icon(Icons.close), tooltip: 'Close', onPressed: () => Navigator.pop(ctx)),
                ],
              ),
              Flexible(
                child: SingleChildScrollView(
                  child: _WideTable(
                    DataTable(
                      columns: [
                        _column('Time'),
                        _column('Invoice'),
                        _column('Product'),
                        _column('SKU'),
                        _column('Qty', numeric: true),
                        _column('Price', numeric: true),
                        _column('Total', numeric: true),
                        _column('Payment'),
                        _column('Sold by'),
                      ],
                      rows: [
                        for (final sale in daySales)
                          for (final item in sale.items)
                            DataRow(cells: [
                              DataCell(Text(formatTime(sale.createdAt))),
                              DataCell(Text(sale.pendingSync ? 'Not synced' : sale.invoiceNumber)),
                              DataCell(Text(item.name)),
                              DataCell(Text(item.sku ?? '—')),
                              DataCell(Text(formatQuantity(item.quantity))),
                              DataCell(Text(formatCurrency(item.unitPrice))),
                              DataCell(Text(formatCurrency(item.lineTotal))),
                              DataCell(Text(sale.paymentMethod == 'cash' ? 'Cash' : 'Card')),
                              DataCell(Text(sale.cashierName ?? '—')),
                            ]),
                      ],
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _Figure extends StatelessWidget {
  final String label;
  final String value;
  const _Figure({required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 200,
      child: Card(
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(value, style: Theme.of(context).textTheme.titleLarge),
              Text(label, style: Theme.of(context).textTheme.bodySmall),
            ],
          ),
        ),
      ),
    );
  }
}

enum _Period {
  today('Today', 1),
  week('7 days', 7),
  month('${AppDatabase.recordDays} days', AppDatabase.recordDays);

  final String label;
  final int days;
  const _Period(this.label, this.days);

  bool includes(Sale sale) {
    final first = dayOf(DateTime.now()).subtract(Duration(days: days - 1));
    return !dayOf(sale.createdAt).isBefore(first);
  }
}

class _StockRecordTab extends StatefulWidget {
  final List<StockRecordRow> Function(_Period period) rowsFor;
  const _StockRecordTab({required this.rowsFor});

  @override
  State<_StockRecordTab> createState() => _StockRecordTabState();
}

class _StockRecordTabState extends State<_StockRecordTab> {
  _Period _period = _Period.today;
  String _filter = 'all'; // all | sold | low | out

  bool _matches(StockRecordRow row) => switch (_filter) {
        'sold' => row.soldQty > 0,
        'low' => row.state == StockState.low,
        'out' => row.state == StockState.soldOut,
        _ => true,
      };

  @override
  Widget build(BuildContext context) {
    final all = widget.rowsFor(_period);
    final rows = all.where(_matches).toList();
    final soldQty = all.fold<double>(0, (sum, r) => sum + r.soldQty);
    final soldOut = all.where((r) => r.state == StockState.soldOut).length;
    final low = all.where((r) => r.state == StockState.low).length;

    return ListView(
      padding: const EdgeInsets.all(12),
      children: [
        Wrap(
          spacing: 12,
          runSpacing: 8,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            SegmentedButton<_Period>(
              segments: [for (final p in _Period.values) ButtonSegment(value: p, label: Text(p.label))],
              selected: {_period},
              onSelectionChanged: (s) => setState(() => _period = s.first),
            ),
            for (final (key, label) in [
              ('all', 'All products'),
              ('sold', 'Sold (${all.where((r) => r.soldQty > 0).length})'),
              ('low', 'Low stock ($low)'),
              ('out', 'Sold out ($soldOut)'),
            ])
              ChoiceChip(label: Text(label), selected: _filter == key, onSelected: (_) => setState(() => _filter = key)),
          ],
        ),
        const SizedBox(height: 8),
        Text('${formatQuantity(soldQty)} item(s) sold · ${_period.label.toLowerCase()}', style: Theme.of(context).textTheme.bodySmall),
        const SizedBox(height: 8),
        if (rows.isEmpty)
          const Padding(padding: EdgeInsets.only(top: 40), child: Center(child: Text('Nothing to show')))
        else
          _WideTable(
            DataTable(
              columns: [
                _column('Product'),
                _column('SKU'),
                _column('Category'),
                _column('Sold', numeric: true),
                _column('Sales value', numeric: true),
                _column('Remaining', numeric: true),
                _column('Status'),
              ],
              rows: [
                for (final row in rows)
                  DataRow(cells: [
                    DataCell(Text(row.name, style: const TextStyle(fontWeight: FontWeight.w600))),
                    DataCell(Text(row.sku ?? '—')),
                    DataCell(Text(ProductCategory.label(row.category))),
                    DataCell(Text(formatQuantity(row.soldQty))),
                    DataCell(Text(formatCurrency(row.soldValue))),
                    DataCell(Text(row.remaining == null ? '—' : '${row.remaining} ${row.unit}')),
                    DataCell(_StateBadge(state: row.state)),
                  ]),
              ],
            ),
          ),
      ],
    );
  }
}

class _StateBadge extends StatelessWidget {
  final StockState state;
  const _StateBadge({required this.state});

  @override
  Widget build(BuildContext context) {
    final (label, tone) = switch (state) {
      StockState.inStock => ('In stock', StatusTone.success),
      StockState.low => ('Low stock', StatusTone.warning),
      StockState.soldOut => ('Sold out', StatusTone.danger),
      StockState.madeToOrder => ('Made to order', StatusTone.info),
      StockState.removed => ('Removed', StatusTone.neutral),
    };
    return StatusBadge(label: label, tone: tone);
  }
}
