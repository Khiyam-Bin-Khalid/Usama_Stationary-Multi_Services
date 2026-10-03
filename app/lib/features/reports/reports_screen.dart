import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../core/format.dart';
import '../../core/providers.dart';
import '../../core/roles.dart';
import '../../core/theme/app_colors.dart';
import '../../data/models/product.dart';

final _reportProductsProvider = FutureProvider.autoDispose<List<Product>>((ref) => ref.watch(productApiProvider).list());

/// Reports: daily / weekly / monthly / yearly or a custom date range, with
/// filters by source (POS / online), category and product. Revenue and
/// items-sold trends are drawn as line graphs; category and top-product
/// revenue breakdowns follow. Staff see their own daily POS figures only.
class ReportsScreen extends ConsumerStatefulWidget {
  const ReportsScreen({super.key});

  @override
  ConsumerState<ReportsScreen> createState() => _ReportsScreenState();
}

class _ReportsScreenState extends ConsumerState<ReportsScreen> {
  String _period = 'daily';
  String _source = 'all';
  String? _category;
  String? _productId;
  DateTimeRange? _range;
  Map<String, dynamic>? _report;
  List<Map<String, dynamic>> _categories = [];
  List<Map<String, dynamic>> _products = [];
  bool _loading = true;
  String? _error;

  static const _presets = {
    'daily': 'Daily',
    'weekly': 'Weekly',
    'monthly': 'Monthly',
    'yearly': 'Yearly',
  };

  @override
  void initState() {
    super.initState();
    _load();
  }

  /// Default window per period when no custom range is picked.
  (DateTime?, DateTime?) _window() {
    if (_range != null) {
      return (_range!.start, DateTime(_range!.end.year, _range!.end.month, _range!.end.day, 23, 59, 59));
    }
    final now = DateTime.now();
    switch (_period) {
      case 'daily':
        return (now.subtract(const Duration(days: 30)), now);
      case 'weekly':
        return (now.subtract(const Duration(days: 7 * 12)), now);
      case 'monthly':
        return (DateTime(now.year - 1, now.month, 1), now);
      case 'yearly':
        return (DateTime(now.year - 5, 1, 1), now);
    }
    return (null, null);
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final role = ref.read(authStateProvider).valueOrNull?.role;
      final isStaff = role == UserRole.staff;
      final (from, to) = isStaff ? (null, null) : _window();
      final api = ref.read(reportApiProvider);
      final report = await api.salesReport(
        period: isStaff ? 'daily' : _period,
        source: isStaff ? 'pos' : _source,
        category: _category,
        productId: _productId,
        from: from,
        to: to,
      );
      List<Map<String, dynamic>> categories = [];
      List<Map<String, dynamic>> products = [];
      if (!isStaff) {
        categories = await api.categoryReport(from: from, to: to, source: _source);
        products = await api.productReport(from: from, to: to, source: _source, category: _category, limit: 10);
      }
      if (!mounted) return;
      setState(() {
        _report = report;
        _categories = categories;
        _products = products;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e.toString();
        _loading = false;
      });
    }
  }

  Future<void> _pickRange() async {
    final now = DateTime.now();
    final picked = await showDateRangePicker(
      context: context,
      firstDate: DateTime(now.year - 5),
      lastDate: now,
      initialDateRange: _range,
    );
    if (picked == null) return;
    setState(() => _range = picked);
    _load();
  }

  @override
  Widget build(BuildContext context) {
    final role = ref.watch(authStateProvider).valueOrNull?.role ?? UserRole.staff;
    final isStaff = role == UserRole.staff;
    final products = ref.watch(_reportProductsProvider).valueOrNull ?? const <Product>[];

    final summary = _report?['summary'] as Map<String, dynamic>? ?? {};
    final buckets = (_report?['buckets'] as List? ?? []).cast<Map<String, dynamic>>();

    return RefreshIndicator(
      onRefresh: _load,
      child: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Text(isStaff ? 'My sales today' : 'Reports & analytics', style: Theme.of(context).textTheme.titleLarge),
          const SizedBox(height: 12),
          if (!isStaff) ...[
            Wrap(
              spacing: 8,
              runSpacing: 8,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                for (final e in _presets.entries)
                  ChoiceChip(
                    label: Text(e.value),
                    selected: _period == e.key && _range == null,
                    onSelected: (_) {
                      setState(() {
                        _period = e.key;
                        _range = null;
                      });
                      _load();
                    },
                  ),
                ActionChip(
                  avatar: const Icon(Icons.date_range, size: 18),
                  label: Text(_range == null
                      ? 'Custom range'
                      : '${formatPeriodLabel(_range!.start, 'daily')} – ${formatPeriodLabel(_range!.end, 'daily')}'),
                  backgroundColor: _range != null ? AppColors.tint(AppColors.primaryOrange) : null,
                  onPressed: _pickRange,
                ),
                if (_range != null)
                  IconButton(
                    tooltip: 'Clear range',
                    icon: const Icon(Icons.close, size: 18),
                    onPressed: () {
                      setState(() => _range = null);
                      _load();
                    },
                  ),
              ],
            ),
            const SizedBox(height: 8),
            Wrap(
              spacing: 12,
              runSpacing: 8,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                SegmentedButton<String>(
                  segments: const [
                    ButtonSegment(value: 'all', label: Text('All')),
                    ButtonSegment(value: 'pos', label: Text('POS')),
                    ButtonSegment(value: 'online', label: Text('Online')),
                  ],
                  selected: {_source},
                  onSelectionChanged: (s) {
                    setState(() => _source = s.first);
                    _load();
                  },
                ),
                DropdownButton<String?>(
                  value: _category,
                  hint: const Text('All categories'),
                  items: [
                    const DropdownMenuItem<String?>(value: null, child: Text('All categories')),
                    for (final c in ProductCategory.all) DropdownMenuItem<String?>(value: c, child: Text(ProductCategory.label(c))),
                  ],
                  onChanged: (v) {
                    setState(() {
                      _category = v;
                      _productId = null;
                    });
                    _load();
                  },
                ),
                ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 320),
                  child: DropdownButton<String?>(
                    value: _productId,
                    isExpanded: true,
                    hint: const Text('All products'),
                    items: [
                      const DropdownMenuItem<String?>(value: null, child: Text('All products')),
                      for (final p in products.where((p) => _category == null || p.category == _category))
                        DropdownMenuItem<String?>(value: p.id, child: Text('${p.name} (${p.sku})', overflow: TextOverflow.ellipsis)),
                    ],
                    onChanged: (v) {
                      setState(() => _productId = v);
                      _load();
                    },
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
          ],
          if (_loading)
            const Padding(padding: EdgeInsets.all(48), child: Center(child: CircularProgressIndicator()))
          else if (_error != null)
            Padding(padding: const EdgeInsets.all(24), child: Text('Failed to load report: $_error', style: const TextStyle(color: AppColors.accentRed)))
          else ...[
            LayoutBuilder(
              builder: (context, c) {
                final tiles = [
                  _SummaryTile(label: 'Revenue', value: formatCurrency(summary['totalRevenue'] ?? 0)),
                  _SummaryTile(label: 'Tax collected', value: formatCurrency(summary['totalTax'] ?? 0)),
                  _SummaryTile(label: 'Items sold', value: '${summary['totalItemsSold'] ?? 0}'),
                ];
                if (c.maxWidth < 520) {
                  return Column(children: [for (final t in tiles) Padding(padding: const EdgeInsets.only(bottom: 8), child: t)]);
                }
                return Row(children: [for (var i = 0; i < tiles.length; i++) ...[if (i > 0) const SizedBox(width: 12), Expanded(child: tiles[i])]]);
              },
            ),
            const SizedBox(height: 24),
            Text('Revenue trend', style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 12),
            _TrendChart(buckets: buckets, valueKey: 'revenue', period: _period, color: AppColors.primaryOrange, currency: true),
            const SizedBox(height: 24),
            Text('Items sold', style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 12),
            _TrendChart(buckets: buckets, valueKey: 'itemsSold', period: _period, color: AppColors.success, currency: false),
            if (!isStaff && _categories.isNotEmpty) ...[
              const SizedBox(height: 32),
              Text('Revenue by category', style: Theme.of(context).textTheme.titleMedium),
              const SizedBox(height: 12),
              for (final c in _categories)
                _BreakdownRow(
                  label: ProductCategory.label(c['category'] as String),
                  value: (c['revenue'] as num).toDouble(),
                  max: (_categories.first['revenue'] as num).toDouble(),
                  trailing: '${formatCurrency(c['revenue'] as num)} · ${c['itemsSold']} sold',
                ),
            ],
            if (!isStaff && _products.isNotEmpty) ...[
              const SizedBox(height: 32),
              Text('Top products', style: Theme.of(context).textTheme.titleMedium),
              const SizedBox(height: 12),
              for (final p in _products)
                _BreakdownRow(
                  label: '${p['name']}${p['sku'] != null ? ' (${p['sku']})' : ''}',
                  value: (p['revenue'] as num).toDouble(),
                  max: (_products.first['revenue'] as num).toDouble(),
                  trailing: '${formatCurrency(p['revenue'] as num)} · ${p['itemsSold']} sold',
                ),
            ],
          ],
        ],
      ),
    );
  }
}

/// Line graph of one metric over the report buckets.
class _TrendChart extends StatelessWidget {
  final List<Map<String, dynamic>> buckets;
  final String valueKey;
  final String period;
  final Color color;
  final bool currency;
  const _TrendChart({required this.buckets, required this.valueKey, required this.period, required this.color, required this.currency});

  @override
  Widget build(BuildContext context) {
    if (buckets.isEmpty) {
      return const SizedBox(height: 200, child: Center(child: Text('No sales in this period yet')));
    }
    final spots = [
      for (var i = 0; i < buckets.length; i++) FlSpot(i.toDouble(), (buckets[i][valueKey] as num? ?? 0).toDouble()),
    ];
    final maxY = spots.fold<double>(0, (m, s) => s.y > m ? s.y : m);
    final labelEvery = (buckets.length / 6).ceil().clamp(1, 1000);

    return SizedBox(
      height: 240,
      child: LineChart(
        LineChartData(
          minY: 0,
          maxY: maxY == 0 ? 1 : maxY * 1.15,
          lineTouchData: LineTouchData(
            touchTooltipData: LineTouchTooltipData(
              getTooltipItems: (touched) => touched
                  .map((t) => LineTooltipItem(
                        '${formatPeriodLabel(DateTime.parse(buckets[t.x.toInt()]['period'] as String), period)}\n${currency ? formatCurrency(t.y) : t.y.toInt().toString()}',
                        const TextStyle(color: Colors.white, fontWeight: FontWeight.w600),
                      ))
                  .toList(),
            ),
          ),
          lineBarsData: [
            LineChartBarData(
              spots: spots,
              isCurved: buckets.length > 2,
              curveSmoothness: 0.25,
              preventCurveOverShooting: true,
              color: color,
              barWidth: 3,
              dotData: FlDotData(show: buckets.length <= 31),
              belowBarData: BarAreaData(show: true, color: color.withValues(alpha: 0.12)),
            ),
          ],
          titlesData: FlTitlesData(
            bottomTitles: AxisTitles(
              sideTitles: SideTitles(
                showTitles: true,
                reservedSize: 28,
                interval: 1,
                getTitlesWidget: (value, meta) {
                  final i = value.toInt();
                  if (i < 0 || i >= buckets.length || i % labelEvery != 0) return const SizedBox.shrink();
                  return Padding(
                    padding: const EdgeInsets.only(top: 6),
                    child: Text(
                      formatPeriodLabel(DateTime.parse(buckets[i]['period'] as String), period),
                      style: const TextStyle(fontSize: 10, color: AppColors.textSecondary),
                    ),
                  );
                },
              ),
            ),
            leftTitles: AxisTitles(
              sideTitles: SideTitles(
                showTitles: true,
                reservedSize: 52,
                getTitlesWidget: (value, meta) => Text(
                  currency ? _compact(value) : value.toInt().toString(),
                  style: const TextStyle(fontSize: 10, color: AppColors.textSecondary),
                ),
              ),
            ),
            topTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
            rightTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
          ),
          borderData: FlBorderData(show: false),
          gridData: const FlGridData(show: true, drawVerticalLine: false),
        ),
      ),
    );
  }

  static String _compact(double v) {
    if (v >= 1000000) return '${(v / 1000000).toStringAsFixed(1)}M';
    if (v >= 1000) return '${(v / 1000).toStringAsFixed(v >= 10000 ? 0 : 1)}k';
    return v.toInt().toString();
  }
}

class _BreakdownRow extends StatelessWidget {
  final String label;
  final double value;
  final double max;
  final String trailing;
  const _BreakdownRow({required this.label, required this.value, required this.max, required this.trailing});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          Expanded(flex: 3, child: Text(label, maxLines: 1, overflow: TextOverflow.ellipsis)),
          Expanded(
            flex: 4,
            child: LinearProgressIndicator(
              value: max <= 0 ? 0 : (value / max).clamp(0, 1),
              minHeight: 8,
              borderRadius: BorderRadius.circular(4),
            ),
          ),
          const SizedBox(width: 8),
          Text(trailing, style: Theme.of(context).textTheme.bodySmall),
        ],
      ),
    );
  }
}

class _SummaryTile extends StatelessWidget {
  final String label;
  final String value;
  const _SummaryTile({required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(label, style: Theme.of(context).textTheme.bodySmall),
            const SizedBox(height: 6),
            Text(value, style: Theme.of(context).textTheme.titleLarge),
          ],
        ),
      ),
    );
  }
}
