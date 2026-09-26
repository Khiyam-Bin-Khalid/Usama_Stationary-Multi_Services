import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../core/format.dart';
import '../../core/providers.dart';
import '../../core/roles.dart';

class ReportsScreen extends ConsumerStatefulWidget {
  const ReportsScreen({super.key});

  @override
  ConsumerState<ReportsScreen> createState() => _ReportsScreenState();
}

class _ReportsScreenState extends ConsumerState<ReportsScreen> {
  String _period = 'daily';
  Map<String, dynamic>? _report;
  List<Map<String, dynamic>> _categories = [];
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final report = await ref.read(reportApiProvider).salesReport(period: _period);
      List<Map<String, dynamic>> categories = [];
      final role = ref.read(authStateProvider).valueOrNull?.role;
      if (role != UserRole.staff) {
        categories = await ref.read(reportApiProvider).categoryReport();
      }
      if (!mounted) return;
      setState(() {
        _report = report;
        _categories = categories;
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

  @override
  Widget build(BuildContext context) {
    final role = ref.watch(authStateProvider).valueOrNull?.role ?? UserRole.staff;
    final isStaff = role == UserRole.staff;

    if (_loading) return const Center(child: CircularProgressIndicator());
    if (_error != null) return Center(child: Text('Failed to load report: $_error'));

    final summary = _report?['summary'] as Map<String, dynamic>? ?? {};
    final buckets = (_report?['buckets'] as List? ?? []).cast<Map<String, dynamic>>();

    return RefreshIndicator(
      onRefresh: _load,
      child: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          if (!isStaff)
            SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(
                children: [
                  for (final p in ['daily', 'weekly', 'monthly', 'yearly'])
                    Padding(
                      padding: const EdgeInsets.only(right: 8),
                      child: ChoiceChip(
                        label: Text(p[0].toUpperCase() + p.substring(1)),
                        selected: _period == p,
                        onSelected: (_) {
                          setState(() => _period = p);
                          _load();
                        },
                      ),
                    ),
                ],
              ),
            ),
          const SizedBox(height: 16),
          Row(
            children: [
              Expanded(child: _SummaryTile(label: 'Revenue', value: formatCurrency(summary['totalRevenue'] ?? 0))),
              const SizedBox(width: 12),
              Expanded(child: _SummaryTile(label: 'Tax collected', value: formatCurrency(summary['totalTax'] ?? 0))),
              const SizedBox(width: 12),
              Expanded(child: _SummaryTile(label: 'Items sold', value: '${summary['totalItemsSold'] ?? 0}')),
            ],
          ),
          const SizedBox(height: 24),
          Text('Revenue over time', style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 12),
          SizedBox(
            height: 240,
            child: buckets.isEmpty
                ? const Center(child: Text('No sales in this period yet'))
                : BarChart(
                    BarChartData(
                      barGroups: [
                        for (var i = 0; i < buckets.length; i++)
                          BarChartGroupData(x: i, barRods: [
                            BarChartRodData(
                              toY: (buckets[i]['revenue'] as num).toDouble(),
                              color: Theme.of(context).colorScheme.primary,
                              width: 16,
                              borderRadius: BorderRadius.circular(4),
                            ),
                          ]),
                      ],
                      titlesData: FlTitlesData(
                        bottomTitles: AxisTitles(
                          sideTitles: SideTitles(
                            showTitles: true,
                            getTitlesWidget: (value, meta) {
                              final i = value.toInt();
                              if (i < 0 || i >= buckets.length) return const SizedBox.shrink();
                              return Padding(
                                padding: const EdgeInsets.only(top: 6),
                                child: Text(
                                  DateTime.parse(buckets[i]['period']).day.toString(),
                                  style: const TextStyle(fontSize: 10),
                                ),
                              );
                            },
                          ),
                        ),
                        leftTitles: const AxisTitles(sideTitles: SideTitles(showTitles: true, reservedSize: 48)),
                        topTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                        rightTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                      ),
                      borderData: FlBorderData(show: false),
                      gridData: const FlGridData(show: true, drawVerticalLine: false),
                    ),
                  ),
          ),
          if (!isStaff && _categories.isNotEmpty) ...[
            const SizedBox(height: 32),
            Text('Revenue by category', style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 12),
            for (final c in _categories)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 4),
                child: Row(
                  children: [
                    Expanded(flex: 2, child: Text(c['category'] as String)),
                    Expanded(
                      flex: 5,
                      child: LinearProgressIndicator(
                        value: (c['revenue'] as num) / (_categories.first['revenue'] as num).clamp(1, double.infinity),
                        minHeight: 8,
                        borderRadius: BorderRadius.circular(4),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Text(formatCurrency(c['revenue'] as num)),
                  ],
                ),
              ),
          ],
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
