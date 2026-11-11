import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../core/providers.dart';
import '../../data/local/app_database.dart';
import '../../data/models/product.dart';
import '../../data/models/sale.dart';
import '../../data/repositories/inventory_repository.dart';

bool isToday(DateTime dt) {
  final now = DateTime.now();
  final local = dt.toLocal();
  return local.year == now.year && local.month == now.month && local.day == now.day;
}

DateTime dayOf(DateTime dt) {
  final local = dt.toLocal();
  return DateTime(local.year, local.month, local.day);
}

/// Sales of the last [AppDatabase.recordDays] days. Desktop/mobile read the
/// local database, so the records work the same online and offline and update
/// live as sales are made; web has no local store and asks the API.
final recordSalesProvider = StreamProvider.autoDispose<List<Sale>>((ref) {
  final now = DateTime.now();
  final to = DateTime(now.year, now.month, now.day, 23, 59, 59);
  final from = dayOf(now).subtract(const Duration(days: AppDatabase.recordDays - 1));
  final db = ref.watch(appDatabaseProvider);
  if (db != null) return db.watchLocalSalesInRange(from, to);
  return Stream.fromFuture(ref.watch(saleApiProvider).listAllSales(from: from, to: to));
});

final recordProductsProvider = StreamProvider.autoDispose<List<Product>>((ref) {
  final db = ref.watch(appDatabaseProvider);
  if (db != null) return db.watchActiveProducts().map((rows) => rows.map(productFromCache).toList());
  return Stream.fromFuture(ref.watch(productApiProvider).list());
});

/// One line of the daily sales table.
class DailySalesRow {
  final DateTime day;
  final int invoices;
  final double itemsSold;
  final double cash;
  final double card;
  final int notSynced;

  const DailySalesRow({
    required this.day,
    required this.invoices,
    required this.itemsSold,
    required this.cash,
    required this.card,
    required this.notSynced,
  });

  double get revenue => cash + card;
}

/// Totals per calendar day (device time zone), newest first.
List<DailySalesRow> summariseByDay(Iterable<Sale> sales) {
  final byDay = <DateTime, List<Sale>>{};
  for (final sale in sales) {
    byDay.putIfAbsent(dayOf(sale.createdAt), () => []).add(sale);
  }
  final rows = byDay.entries.map((entry) {
    double sum(bool Function(Sale) test) => entry.value.where(test).fold(0, (total, s) => total + s.total);
    return DailySalesRow(
      day: entry.key,
      invoices: entry.value.length,
      itemsSold: entry.value.expand((s) => s.items).fold(0, (total, i) => total + i.quantity),
      cash: sum((s) => s.paymentMethod == 'cash'),
      card: sum((s) => s.paymentMethod != 'cash'),
      notSynced: entry.value.where((s) => s.pendingSync).length,
    );
  }).toList();
  rows.sort((a, b) => b.day.compareTo(a.day));
  return rows;
}

enum StockState { inStock, low, soldOut, madeToOrder, removed }

/// One line of the stock record: what sold in the period and what's left.
class StockRecordRow {
  final String name;
  final String? sku;
  final String category;
  final String unit;
  final double soldQty;
  final double soldValue;
  final int? remaining; // null when the product no longer exists
  final StockState state;

  const StockRecordRow({
    required this.name,
    required this.sku,
    required this.category,
    required this.unit,
    required this.soldQty,
    required this.soldValue,
    required this.remaining,
    required this.state,
  });
}

/// Every active product with its sales in [sales], plus anything sold in the
/// period that has since been deleted. Best sellers first, then by name.
List<StockRecordRow> buildStockRecord(Iterable<Sale> sales, List<Product> products) {
  final sold = <String, ({SaleLineItem line, double qty, double value})>{};
  for (final item in sales.expand((s) => s.items)) {
    final seen = sold[item.productId];
    sold[item.productId] = (line: item, qty: (seen?.qty ?? 0) + item.quantity, value: (seen?.value ?? 0) + item.lineTotal);
  }

  final rows = [
    for (final p in products)
      StockRecordRow(
        name: p.name,
        sku: p.sku,
        category: p.category,
        unit: p.unit,
        soldQty: sold[p.id]?.qty ?? 0,
        soldValue: sold[p.id]?.value ?? 0,
        remaining: p.isMadeToOrder ? null : p.currentStock,
        state: p.isMadeToOrder
            ? StockState.madeToOrder
            : p.isOutOfStock
                ? StockState.soldOut
                : p.isLowStock
                    ? StockState.low
                    : StockState.inStock,
      ),
  ];

  final activeIds = {for (final p in products) p.id};
  for (final entry in sold.entries.where((e) => !activeIds.contains(e.key))) {
    final line = entry.value.line;
    rows.add(StockRecordRow(
      name: line.name,
      sku: line.sku,
      category: line.category,
      unit: '',
      soldQty: entry.value.qty,
      soldValue: entry.value.value,
      remaining: null,
      state: StockState.removed,
    ));
  }

  rows.sort((a, b) {
    final bySold = b.soldQty.compareTo(a.soldQty);
    return bySold != 0 ? bySold : a.name.toLowerCase().compareTo(b.name.toLowerCase());
  });
  return rows;
}
