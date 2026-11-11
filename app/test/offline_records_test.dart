import 'dart:io';

import 'package:drift/drift.dart' hide isNull, isNotNull;
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqlite3/sqlite3.dart' as raw;
import 'package:usama_book_depot/data/local/app_database.dart';
import 'package:usama_book_depot/data/models/product.dart';
import 'package:usama_book_depot/data/models/sale.dart';
import 'package:usama_book_depot/data/repositories/offline_credentials.dart';
import 'package:usama_book_depot/features/reports/daily_records_screen.dart';
import 'package:usama_book_depot/features/reports/records_providers.dart';

import 'support/sqlite.dart';

Sale sale(String id, DateTime at, double total, {String pay = 'cash', bool pending = false, String product = 'p1', String name = 'Pen', double qty = 1}) => Sale(
      id: id,
      clientTxnId: id,
      invoiceNumber: pending ? 'PENDING' : 'INV-$id',
      items: [SaleLineItem(productId: product, name: name, sku: 'STN-1', category: 'stationery', unitPrice: total / qty, quantity: qty, lineTotal: total)],
      subtotal: total,
      taxAmount: 0,
      total: total,
      paymentMethod: pay,
      createdAt: at,
      recordedOffline: pending,
      cashierName: 'Bilal',
      pendingSync: pending,
    );

Product product(String id, String name, int stock, {int reorder = 2, bool madeToOrder = false}) => Product(
      id: id,
      name: name,
      sku: 'SKU-$id',
      category: 'stationery',
      unit: 'pcs',
      price: 10,
      costPrice: 5,
      currentStock: stock,
      reorderThreshold: reorder,
      isMadeToOrder: madeToOrder,
      isAvailableOnline: true,
      isActive: true,
    );

void main() {
  useSystemSqlite();

  group('summariseByDay', () {
    test('groups by local calendar day, newest first, split by payment', () {
      final rows = summariseByDay([
        sale('a', DateTime(2026, 11, 5, 9), 100),
        sale('b', DateTime(2026, 11, 5, 23, 59), 50, pay: 'card'),
        sale('c', DateTime(2026, 11, 4, 0, 1), 30, pending: true, qty: 3),
      ]);
      expect(rows.map((r) => r.day), [DateTime(2026, 11, 5), DateTime(2026, 11, 4)]);
      expect(rows[0].revenue, 150);
      expect(rows[0].cash, 100);
      expect(rows[0].card, 50);
      expect(rows[0].invoices, 2);
      expect(rows[0].notSynced, 0);
      expect(rows[1].itemsSold, 3);
      expect(rows[1].notSynced, 1);
    });

    test('a server time in UTC lands on the shop\'s local date', () {
      final lateEvening = DateTime(2026, 11, 5, 23, 30);
      final rows = summariseByDay([sale('a', lateEvening.toUtc(), 10)]);
      expect(rows.single.day, DateTime(2026, 11, 5));
    });
  });

  group('buildStockRecord', () {
    test('shows sold quantity, what remains and the stock state', () {
      final rows = buildStockRecord(
        [sale('a', DateTime(2026, 11, 5), 30, qty: 3, product: 'pen', name: 'Pen'), sale('b', DateTime(2026, 11, 5), 20, qty: 2, product: 'pen', name: 'Pen')],
        [product('pen', 'Pen', 0), product('ruler', 'Ruler', 2), product('book', 'Book', 50), product('print', 'Printing', 0, madeToOrder: true)],
      );
      final byName = {for (final r in rows) r.name: r};
      expect(rows.first.name, 'Pen');
      expect(byName['Pen']!.soldQty, 5);
      expect(byName['Pen']!.soldValue, 50);
      expect(byName['Pen']!.remaining, 0);
      expect(byName['Pen']!.state, StockState.soldOut);
      expect(byName['Ruler']!.state, StockState.low);
      expect(byName['Book']!.state, StockState.inStock);
      expect(byName['Book']!.soldQty, 0);
      expect(byName['Printing']!.state, StockState.madeToOrder);
      expect(byName['Printing']!.remaining, isNull);
    });

    test('keeps a product deleted after it was sold', () {
      final rows = buildStockRecord([sale('a', DateTime(2026, 11, 5), 10, product: 'gone', name: 'Old Stock')], []);
      expect(rows.single.state, StockState.removed);
      expect(rows.single.soldQty, 1);
    });
  });

  group('offline credentials', () {
    test('verifies the right password only, salted per account', () async {
      final salt = OfflineCredentials.newSalt();
      final hash = await OfflineCredentials.hash('Secret123', salt, 1000);
      expect(OfflineCredentials.matches(hash, await OfflineCredentials.hash('Secret123', salt, 1000)), isTrue);
      expect(OfflineCredentials.matches(hash, await OfflineCredentials.hash('secret123', salt, 1000)), isFalse);
      expect(hash, isNot(await OfflineCredentials.hash('Secret123', OfflineCredentials.newSalt(), 1000)));
      expect(hash, isNot(contains('Secret123')));
    });
  });

  test('the waiting count follows both sales and product changes', () async {
    final db = AppDatabase(NativeDatabase.memory());
    addTearDown(db.close);
    final counts = db.watchUnsyncedCount();

    expect(await counts.first, 0);
    await db.queueOp(opId: 'op-1', type: 'stock_adjust', productId: 'p1', label: 'Stock +1');
    expect(await counts.first, 1);
    await db.queueSale(clientTxnId: 'pos-1', items: const [], paymentMethod: 'cash', createdAt: DateTime(2026, 11, 5));
    expect(await counts.first, 2);
    await db.markSynced('pos-1');
    await db.removeOp(1);
    await expectLater(counts, emits(0));
  });

  // Real devices already hold a v3 database, possibly with sales stuck in the
  // queue from before the push payload was fixed.
  test('migrating a v3 database keeps stuck sales and makes them sendable', () async {
    final dir = Directory.systemTemp.createTempSync('usama-migration');
    addTearDown(() => dir.deleteSync(recursive: true));
    final file = File('${dir.path}/v3.sqlite');
    final old = raw.sqlite3.open(file.path);
    old.execute('''
      CREATE TABLE products_cache (id TEXT NOT NULL PRIMARY KEY, name TEXT NOT NULL, sku TEXT NOT NULL, barcode TEXT, image_url TEXT,
        category TEXT NOT NULL, unit TEXT NOT NULL, price REAL NOT NULL, cost_price REAL NOT NULL, current_stock INTEGER NOT NULL,
        reorder_threshold INTEGER NOT NULL, is_made_to_order INTEGER NOT NULL, is_available_online INTEGER NOT NULL, is_active INTEGER NOT NULL, updated_at INTEGER NOT NULL);
      CREATE TABLE promotions_cache (id TEXT NOT NULL PRIMARY KEY, name TEXT NOT NULL, discount_type TEXT NOT NULL, discount_value REAL NOT NULL,
        categories_json TEXT NOT NULL, start_date INTEGER NOT NULL, end_date INTEGER NOT NULL);
      CREATE TABLE pending_sales (client_txn_id TEXT NOT NULL PRIMARY KEY, items_json TEXT NOT NULL, payment_method TEXT NOT NULL,
        created_at INTEGER NOT NULL, synced INTEGER NOT NULL DEFAULT 0, sync_error TEXT);
      CREATE TABLE sync_meta (key TEXT NOT NULL PRIMARY KEY, value TEXT NOT NULL);
      CREATE TABLE local_sales_cache (client_txn_id TEXT NOT NULL PRIMARY KEY, sale_json TEXT NOT NULL, created_at INTEGER NOT NULL, pending INTEGER NOT NULL DEFAULT 0);
      INSERT INTO pending_sales (client_txn_id, items_json, payment_method, created_at)
        VALUES ('pos-stuck', '[{"productId":"abc","quantity":2,"name":"Pen","unitPrice":10}]', 'cash', 1790000000);
      INSERT INTO sync_meta (key, value) VALUES ('lastSync', '2026-10-01T00:00:00.000Z');
      PRAGMA user_version = 3;
    ''');
    old.dispose();

    final db = AppDatabase(NativeDatabase(file));
    addTearDown(db.close);
    final queued = (await db.unsyncedSales()).single;
    expect(queued.clientTxnId, 'pos-stuck');
    expect(queued.productIds, ['abc']);
    expect(queued.cashierId, isNull);
    expect(await db.allPendingOps(), isEmpty);
    expect(await db.lastSyncTime(), isNull, reason: 'a full re-pull fills in descriptions');
  });

  testWidgets('daily records fit a phone screen and open a date\'s detail', (tester) async {
    tester.view.physicalSize = const Size(390, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final now = DateTime.now();

    await tester.pumpWidget(ProviderScope(
      overrides: [
        recordSalesProvider.overrideWith((ref) => Stream.value([
              sale('today', now, 500, name: 'Marker', qty: 5, pending: true),
              sale('yesterday', now.subtract(const Duration(days: 1)), 80),
            ])),
        recordProductsProvider.overrideWith((ref) => Stream.value([product('p1', 'Marker', 0)])),
      ],
      child: const MaterialApp(home: Scaffold(body: DailyRecordsScreen())),
    ));
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
    expect(find.text('Rs. 500'), findsWidgets); // today's figure + its row

    await tester.tap(find.textContaining(RegExp(r'^\w{3}, \d+ \w{3} \d{4}$')).first);
    await tester.pumpAndSettle();
    expect(find.textContaining('Sales on'), findsOneWidget);
    expect(find.text('Not synced'), findsWidgets);
    expect(find.text('Marker'), findsOneWidget);
    expect(tester.takeException(), isNull);
    await tester.tap(find.byTooltip('Close'));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Stock record'));
    await tester.pumpAndSettle();
    expect(find.text('Sold out'), findsWidgets);
    await tester.tap(find.text('Sold out (1)'));
    await tester.pumpAndSettle();
    expect(find.text('Marker'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
