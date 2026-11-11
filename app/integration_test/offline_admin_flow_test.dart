// Drives the real desktop app through its real screens: an Admin signs in
// online, loses the connection, signs back in offline, adds a product, makes a
// sale, reads the daily records, and then syncs. Needs the throwaway stack:
//
//   node backend/scripts/e2e-stack.js
//   flutter test integration_test/offline_admin_flow_test.dart -d linux
//
// It uses a temporary database and in-memory secure storage, so it never
// touches the app's real data or the desktop keyring.
import 'dart:io';
import 'dart:ui' as ui;

import 'package:dio/dio.dart';
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:integration_test/integration_test.dart';
import 'package:usama_book_depot/core/providers.dart';
import 'package:usama_book_depot/core/router/app_router.dart';
import 'package:usama_book_depot/data/local/app_database.dart';
import 'package:usama_book_depot/data/remote/api_client.dart';
import 'package:usama_book_depot/data/repositories/sync_service.dart';
import 'package:usama_book_depot/main.dart';

import '../test/e2e/kill_switch_proxy.dart';

const proxyPort = 4101;
const direct = 'http://127.0.0.1:4100/api';
const screenshotDir = String.fromEnvironment('SCREENSHOT_DIR');

final _boundary = GlobalKey();

Future<void> shot(WidgetTester tester, String name) async {
  if (screenshotDir.isEmpty) return;
  await tester.pump(const Duration(milliseconds: 400));
  final render = _boundary.currentContext!.findRenderObject()! as RenderRepaintBoundary;
  await tester.runAsync(() async {
    final image = await render.toImage(pixelRatio: 1);
    final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
    await File('$screenshotDir/$name.png').writeAsBytes(bytes!.buffer.asUint8List());
  });
}

Future<void> pumpUntil(WidgetTester tester, Finder finder, {Duration timeout = const Duration(seconds: 30)}) async {
  final end = DateTime.now().add(timeout);
  while (DateTime.now().isBefore(end)) {
    await tester.pump(const Duration(milliseconds: 100));
    if (finder.evaluate().isNotEmpty) return;
  }
  throw TestFailure('Timed out waiting for $finder');
}

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('admin works a full offline session through the UI', (tester) async {
    FlutterSecureStorage.setMockInitialValues({});
    final proxy = KillSwitchProxy(port: proxyPort, upstreamPort: 4100);
    await proxy.start();
    addTearDown(proxy.stop);

    // A fresh admin account for this run, created by the owner.
    final stamp = DateTime.now().millisecondsSinceEpoch;
    final email = 'ui.admin.$stamp@example.com';
    const password = 'UiAdminPass123';
    final productName = 'UI Offline Marker $stamp';
    final owner = Dio(BaseOptions(baseUrl: direct));
    final login = await owner.post('/auth/login', data: {'email': 'owner@example.com', 'password': 'OwnerPass123'});
    owner.options.headers['Authorization'] = 'Bearer ${login.data['accessToken']}';
    await owner.post('/auth/staff', data: {'name': 'Uzma Admin', 'email': email, 'password': password, 'role': 'admin'});

    final dir = await Directory.systemTemp.createTemp('usama-ui-test');
    final db = AppDatabase(NativeDatabase(File('${dir.path}/test.sqlite')));
    final container = ProviderContainer(overrides: [
      apiClientProvider.overrideWith((ref) => ApiClient(ref.watch(tokenStorageProvider), baseUrl: 'http://127.0.0.1:$proxyPort/api')),
      appDatabaseProvider.overrideWithValue(db),
    ]);
    addTearDown(container.dispose);

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: RepaintBoundary(key: _boundary, child: const UsamaBookDepotApp()),
      ),
    );
    GoRouter router() => container.read(goRouterProvider);
    SyncService sync() => container.read(syncServiceProvider)!;

    Future<void> signIn() async {
      await pumpUntil(tester, find.text('Sign in as'));
      await tester.tap(find.text('Admin'));
      await tester.pump();
      await tester.enterText(find.widgetWithText(TextFormField, 'Email'), email);
      await tester.enterText(find.widgetWithText(TextFormField, 'Password'), password);
      await tester.tap(find.text('Log in as Admin'));
    }

    // ── Online: first sign-in on this device ────────────────────────────
    await signIn();
    await pumpUntil(tester, find.textContaining('Hello, Uzma Admin'));
    await pumpUntil(tester, find.text('Synced with server'));
    await shot(tester, '1-online-dashboard');

    // ── The connection drops, and the session ends ──────────────────────
    proxy.mode = ProxyMode.down;
    await tester.runAsync(() => sync().syncNow());
    await pumpUntil(tester, find.textContaining('Offline — saving on this device'));
    await tester.tap(find.text('Log out'));

    // ── Offline sign-in lands on a working dashboard ────────────────────
    await signIn();
    await pumpUntil(tester, find.textContaining('working offline'));
    expect(find.textContaining('Could not load'), findsNothing);
    await shot(tester, '2-offline-dashboard');

    // ── Offline: add a product ──────────────────────────────────────────
    router().go('/inventory');
    await pumpUntil(tester, find.text('Add Product'));
    await tester.tap(find.text('Add Product'));
    await pumpUntil(tester, find.text('Save'));
    await tester.enterText(find.widgetWithText(TextFormField, 'Name'), productName);
    await tester.enterText(find.widgetWithText(TextFormField, 'Price (Rs.)'), '40');
    await tester.enterText(find.widgetWithText(TextFormField, 'Initial stock'), '12');
    await tester.tap(find.text('Save'));
    await pumpUntil(tester, find.textContaining('Saved on this device'));
    await tester.enterText(find.byType(TextField).first, productName);
    await pumpUntil(tester, find.text(productName));
    await shot(tester, '3-offline-inventory');

    // ── Offline: sell it ────────────────────────────────────────────────
    router().go('/pos');
    await pumpUntil(tester, find.text('New Sale'));
    await tester.tap(find.text('New Sale'));
    await pumpUntil(tester, find.text('Search products...'));
    await tester.enterText(find.widgetWithText(TextField, 'Search products...'), productName);
    final tile = find.descendant(of: find.byType(Card), matching: find.text(productName));
    await pumpUntil(tester, tile);
    await tester.tap(tile);
    await tester.pump();
    await tester.tap(find.byIcon(Icons.add_circle_outline));
    await tester.pump();
    await pumpUntil(tester, find.textContaining('Complete Sale'));
    await pumpUntil(tester, find.byType(SnackBar).evaluate().isEmpty ? find.byType(Scaffold) : find.textContaining('Complete Sale').hitTestable());
    await tester.tap(find.textContaining('Complete Sale'));
    await pumpUntil(tester, find.textContaining('sale saved locally'));

    // ── Offline: daily records, in table form ───────────────────────────
    router().go('/records');
    await pumpUntil(tester, find.byType(DataTable));
    await shot(tester, '4-offline-daily-sales');

    await tester.tap(find.textContaining(RegExp(r'^\w{3}, \d+ \w{3} \d{4}$')).first);
    await pumpUntil(tester, find.textContaining('Sales on'));
    await pumpUntil(tester, find.text(productName));
    expect(find.text('Rs. 80'), findsWidgets);
    expect(find.text('Not synced'), findsWidgets);
    await shot(tester, '5-offline-day-detail');
    await tester.tap(find.byTooltip('Close'));
    await tester.pump(const Duration(milliseconds: 300));

    await tester.tap(find.text('Stock record'));
    await pumpUntil(tester, find.text(productName)); // best seller today: top of the table
    await tester.pump(const Duration(milliseconds: 500));
    await shot(tester, '6-offline-stock-record');

    // ── Everything is waiting in the sync queue ─────────────────────────
    router().go('/sync');
    await pumpUntil(tester, find.textContaining('waiting to sync'));
    await shot(tester, '7-sync-queue-offline');

    // ── Back online: the queue drains and the server has it all ─────────
    proxy.mode = ProxyMode.up;
    await tester.tap(find.text('Sync now'));
    await pumpUntil(tester, find.textContaining('Everything on this device has reached the server'));
    await pumpUntil(tester, find.text('Synced with server'));
    await shot(tester, '8-synced');

    final found = await Dio(BaseOptions(baseUrl: direct)).get('/products', queryParameters: {'q': productName});
    final product = (found.data['products'] as List).single as Map<String, dynamic>;
    expect(product['currentStock'], 10);
    expect(product['sku'], matches(RegExp(r'^STN-\d{5}$')));
    final sales = await owner.get('/sales', queryParameters: {'limit': 5});
    final sale = (sales.data['sales'] as List).firstWhere((s) => s['items'][0]['product'] == product['_id']);
    expect(sale['total'], 80);
    expect(sale['recordedOffline'], isTrue);
    expect(sale['cashier']['name'], 'Uzma Admin');

    // The sync timers must not outlive the test.
    container.invalidate(syncServiceProvider);
    await db.close();
  });
}
