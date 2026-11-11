// End-to-end: the app's real data layer against the real API.
//
//   node backend/scripts/e2e-stack.js                   # in another terminal
//   E2E_STACK=1 flutter test test/e2e/backend_e2e_test.dart
//
// Skipped in a plain `flutter test`, because it needs that stack running.
import 'dart:convert';
import 'dart:ffi';
import 'dart:io';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:drift/drift.dart' show driftRuntimeOptions;
import 'package:drift/native.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqlite3/open.dart';
import 'package:usama_book_depot/data/local/app_database.dart';
import 'package:usama_book_depot/data/models/cart_item.dart';
import 'package:usama_book_depot/data/models/product.dart';
import 'package:usama_book_depot/data/models/sale.dart';
import 'package:usama_book_depot/data/models/user.dart';
import 'package:usama_book_depot/data/remote/api_client.dart';
import 'package:usama_book_depot/data/remote/audit_api.dart';
import 'package:usama_book_depot/data/remote/auth_api.dart';
import 'package:usama_book_depot/data/remote/discrepancy_api.dart';
import 'package:usama_book_depot/data/remote/inventory_api.dart';
import 'package:usama_book_depot/data/remote/notification_api.dart';
import 'package:usama_book_depot/data/remote/order_api.dart';
import 'package:usama_book_depot/data/remote/payment_api.dart';
import 'package:usama_book_depot/data/remote/product_api.dart';
import 'package:usama_book_depot/data/remote/promotion_api.dart';
import 'package:usama_book_depot/data/remote/report_api.dart';
import 'package:usama_book_depot/data/remote/sale_api.dart';
import 'package:usama_book_depot/data/remote/shift_api.dart';
import 'package:usama_book_depot/data/remote/sync_api.dart';
import 'package:usama_book_depot/data/remote/token_storage.dart';
import 'package:usama_book_depot/data/remote/user_api.dart';
import 'package:usama_book_depot/data/repositories/auth_repository.dart';
import 'package:usama_book_depot/data/repositories/inventory_repository.dart';
import 'package:usama_book_depot/data/repositories/pos_repository.dart';
import 'package:usama_book_depot/data/repositories/sync_service.dart';
import 'package:usama_book_depot/features/reports/records_providers.dart';

import 'kill_switch_proxy.dart';

const apiPort = 4100;
const proxyPort = 4101;
const proxyUrl = 'http://127.0.0.1:$proxyPort/api';
const directUrl = 'http://127.0.0.1:$apiPort/api';
const ownerEmail = 'owner@example.com';
const ownerPassword = 'OwnerPass123';
const adminEmail = 'admin.e2e@example.com';
const staffEmail = 'staff.e2e@example.com';
const staffPassword = 'StaffPass123';

/// A 1×1 PNG with a marker appended, so the stand-in Cloudinary can confirm
/// these exact bytes arrived.
final pngBytes = Uint8List.fromList([
  ...base64Decode('iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mNkYPhfDwAChwGA60e6kgAAAABJRU5ErkJggg=='),
  ...utf8.encode('E2E-IMAGE-MARKER'),
]);

/// Sees the server directly, bypassing the proxy, the way a second device or
/// the web admin would. Used to check what really reached the server.
class Server {
  final Dio dio;
  Server(this.dio);

  static Future<Server> login(String email, String password) async {
    final dio = Dio(BaseOptions(baseUrl: directUrl));
    final res = await dio.post('/auth/login', data: {'email': email, 'password': password});
    dio.options.headers['Authorization'] = 'Bearer ${res.data['accessToken']}';
    return Server(dio);
  }

  Future<Map<String, dynamic>> product(String id) async => (await dio.get('/products/$id')).data['product'] as Map<String, dynamic>;

  Future<List<dynamic>> productsNamed(String name) async => (await dio.get('/products', queryParameters: {'q': name})).data['products'] as List;

  Future<List<Map<String, dynamic>>> sales() async =>
      List<Map<String, dynamic>>.from((await dio.get('/sales', queryParameters: {'limit': 200})).data['sales'] as List);
}

Future<List<dynamic>> cloudinaryUploads() async => (await Dio().get('http://127.0.0.1:4102/__uploads')).data as List;

/// The app's whole data layer, wired exactly as providers.dart wires it.
class Device {
  final TokenStorage tokens = TokenStorage();
  late final ApiClient client = ApiClient(tokens, baseUrl: proxyUrl);
  late final AuthRepository auth = AuthRepository(authApi: AuthApi(client), tokenStorage: tokens);
  late final SaleApi saleApi = SaleApi(client);
  late final ProductApi productApi = ProductApi(client);
  late final InventoryRepository inventory = InventoryRepository(db: db, api: productApi, isOffline: () => sync.isOffline);
  late final PosRepository pos = PosRepository(db: db, saleApi: saleApi, isOffline: () => sync.isOffline);
  late final SyncService sync = SyncService(
    db: db,
    productApi: productApi,
    promotionApi: PromotionApi(client),
    syncApi: SyncApi(client),
    saleApi: saleApi,
    tokenStorage: tokens,
    currentUser: () => user,
  );
  final AppDatabase db;
  AppUser? user;

  Device(this.db);

  Future<AppUser> login(String email, String password, String role) async => user = await auth.login(email, password, role: role);

  Future<void> logout() async {
    await auth.logout();
    user = null;
  }

  Future<Product> cached(String id) async => productFromCache((await db.productById(id))!);

  Future<SaleRecordResult> sell(Product product, num quantity, {String payment = 'cash'}) => pos.recordSale(
        items: [CartItem(product: product, quantity: quantity)],
        paymentMethod: payment,
        cashierId: user?.id,
        cashierName: user?.name,
      );
}

void main() {
  if (Platform.environment['E2E_STACK'] != '1') {
    test('backend e2e', () {}, skip: 'Start backend/scripts/e2e-stack.js and set E2E_STACK=1');
    return;
  }

  driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;
  open.overrideFor(OperatingSystem.linux, () => DynamicLibrary.open('libsqlite3.so.0'));
  final proxy = KillSwitchProxy(port: proxyPort, upstreamPort: apiPort);
  late Server owner;
  late Device device;
  late String staffId;
  late Product pen; // ordinary stocked product, shared by the tests below

  setUpAll(() async {
    await proxy.start();
    FlutterSecureStorage.setMockInitialValues({});
    owner = await Server.login(ownerEmail, ownerPassword);
    await owner.dio.post('/auth/staff', data: {'name': 'Ayesha Admin', 'email': adminEmail, 'password': staffPassword, 'role': 'admin'});
    final staff = await owner.dio.post('/auth/staff', data: {'name': 'Bilal Staff', 'email': staffEmail, 'password': staffPassword, 'role': 'staff'});
    staffId = staff.data['user']['_id'] as String;
    device = Device(AppDatabase(NativeDatabase.memory()));
  });

  tearDownAll(() async {
    await proxy.stop();
    await device.db.close();
  });

  setUp(() => proxy.mode = ProxyMode.up);

  group('front end ↔ back end contract', () {
    test('every role signs in and the seeded catalog parses', () async {
      for (final (email, password, role) in [
        (ownerEmail, ownerPassword, 'superadmin'),
        (adminEmail, staffPassword, 'admin'),
        (staffEmail, staffPassword, 'staff'),
      ]) {
        final user = await device.login(email, password, role);
        expect(user.role, role);
        expect((await AuthApi(device.client).me()).email, email);
      }
      final products = await device.productApi.list();
      expect(products.map((p) => p.sku), containsAll(['STN-00001', 'GRO-00001']));
    });

    test('a wrong role tile is refused by the server', () async {
      await expectLater(device.login(staffEmail, staffPassword, 'admin'), throwsA(isA<ApiException>().having((e) => e.statusCode, 'status', 403)));
    });

    test('admin-added product photo goes to Cloudinary and reaches the storefront', () async {
      await device.login(adminEmail, staffPassword, 'admin');
      final before = (await cloudinaryUploads()).length;

      final result = await device.inventory.create({
        'name': 'Cloud Notebook', 'category': 'stationery', 'price': 150.0, 'reorderThreshold': 5,
        'isMadeToOrder': false, 'isAvailableOnline': true, 'barcode': '', 'description': 'Lined', 'currentStock': 20,
      }, image: pngBytes, imageName: 'notebook.png');

      expect(result.queued, isFalse);
      expect(result.imageWarning, isNull);
      expect(result.product.imageUrl, startsWith('https://res.cloudinary.com/'));
      expect(result.product.imageUrl, contains('usama-stationary/products'));

      final uploads = await cloudinaryUploads();
      expect(uploads.length, before + 1);
      expect(uploads.last['folder'], 'usama-stationary/products');
      expect(uploads.last['containsMarker'], isTrue, reason: 'the exact bytes picked in the app must arrive');

      // Anonymous customer on the web store sees the same image.
      final store = await Dio(BaseOptions(baseUrl: directUrl)).get('/products', queryParameters: {'q': 'Cloud Notebook'});
      expect(store.data['products'][0]['imageUrl'], result.product.imageUrl);
    });

    test('super admin upload works, staff is refused', () async {
      await device.login(ownerEmail, ownerPassword, 'superadmin');
      final created = await device.productApi.create({'name': 'Owner Item', 'category': 'sports', 'price': 10, 'currentStock': 1});
      final updated = await device.productApi.uploadImage(created.id, pngBytes, 'ITEM.PNG');
      expect(updated.imageUrl, startsWith('https://res.cloudinary.com/'));

      await device.login(staffEmail, staffPassword, 'staff');
      await expectLater(device.productApi.uploadImage(created.id, pngBytes, 'x.png'), throwsA(isA<ApiException>().having((e) => e.statusCode, 'status', 403)));
    });

    test('a file the server does not accept is refused with a clear message', () async {
      await device.login(adminEmail, staffPassword, 'admin');
      final created = await device.productApi.create({'name': 'Bad Upload', 'category': 'sports', 'price': 10});
      await expectLater(
        device.productApi.uploadImage(created.id, utf8.encode('not an image'), 'notes.txt'),
        throwsA(isA<ApiException>().having((e) => e.message, 'message', contains('Only JPG, PNG, or WEBP'))),
      );
    });

    test('customer order: receipt goes to Cloudinary, admin sees it', () async {
      final auth = AuthApi(device.client);
      final registered = await auth.registerCustomer(name: 'Cara Customer', email: 'cara@example.com', password: 'CaraPass123');
      await device.tokens.save(accessToken: registered.accessToken, refreshToken: registered.refreshToken, role: 'customer');
      final products = await device.productApi.list(sellableOnly: true);
      final item = products.firstWhere((p) => p.name == 'Cloud Notebook');
      final orders = OrderApi(device.client);
      final payments = PaymentApi(device.client);

      final quote = await orders.quote(items: [{'product': item.id, 'quantity': 2}]);
      expect(quote.toString(), isNotEmpty);
      final placed = await orders.placeOrder(
        items: [{'product': item.id, 'quantity': 2}],
        paymentMethod: 'manual_receipt',
        delivery: {'isHomeDelivery': true, 'address': {'line1': 'Street 1', 'city': 'Lahore', 'phone': '03001234567'}},
      );
      final receipt = await payments.uploadReceiptBytes(placed.order.id, pngBytes, 'receipt.png');
      expect(jsonEncode((await cloudinaryUploads()).last['folder']), contains('usama-stationary/receipts'));
      expect(receipt.toString(), isNotEmpty);
      expect((await orders.myOrders()).map((o) => o.id), contains(placed.order.id));
      expect((await orders.myOrder(placed.order.id)).id, placed.order.id);

      await device.login(adminEmail, staffPassword, 'admin');
      expect((await payments.pendingReview()).map((p) => p.order?.id), contains(placed.order.id));
      expect((await orders.getOrder(placed.order.id)).id, placed.order.id);
      await orders.listAll();
      await orders.statusCounts();
    });

    test('every remaining screen API parses a real response', () async {
      await device.login(ownerEmail, ownerPassword, 'superadmin');
      final c = device.client;
      final reports = ReportApi(c);
      await reports.dashboard();
      await reports.salesReport();
      await reports.categoryReport();
      await reports.productReport();
      await NotificationApi(c).list();
      await NotificationApi(c).unreadCount();
      await InventoryApi(c).movements();
      await InventoryApi(c).lowStock();
      await PromotionApi(c).active();
      await PromotionApi(c).allForAdmin();
      await UserApi(c).list();
      await AuditApi(c).list();
      await DiscrepancyApi(c).list();
      await ShiftApi(c).open(openingCash: 500);
      expect(await ShiftApi(c).current(), isNotNull);
      await ShiftApi(c).close(closingCashActual: 500);
      await ShiftApi(c).list();
      await SyncApi(c).pullDeltas(null);
    });
  });

  group('offline login', () {
    setUpAll(() async {
      // These three have signed in on this device while online.
      await device.login(ownerEmail, ownerPassword, 'superadmin');
      await device.login(adminEmail, staffPassword, 'admin');
      await device.login(staffEmail, staffPassword, 'staff');
      await device.logout();
    });

    tearDown(() async {
      if (device.user != null) await device.logout();
    });

    test('super admin, admin and staff can all sign in with no server', () async {
      proxy.mode = ProxyMode.down;
      expect((await device.login(ownerEmail, ownerPassword, 'superadmin')).role, 'superadmin');
      await device.logout();
      expect((await device.login(adminEmail, staffPassword, 'admin')).role, 'admin');
      await device.logout();
      expect((await device.login(staffEmail, staffPassword, 'staff')).role, 'staff');
    });

    test('also works when the API is up but its database is not', () async {
      proxy.mode = ProxyMode.serverError;
      expect((await device.login(adminEmail, staffPassword, 'admin')).role, 'admin');
    });

    test('a restart with no server keeps the session', () async {
      await device.login(adminEmail, staffPassword, 'admin');
      proxy.mode = ProxyMode.down;
      expect((await device.auth.currentUser())?.email, adminEmail);
    });

    test('offline sign-in activates that account, not the previous one', () async {
      proxy.mode = ProxyMode.down;
      final staff = await device.login(staffEmail, staffPassword, 'staff');
      await device.logout();
      await device.login(adminEmail, staffPassword, 'admin');
      proxy.mode = ProxyMode.up;
      expect((await AuthApi(device.client).me()).email, adminEmail);
      expect(staff.email, staffEmail);
    });

    test('wrong password, wrong role and unknown accounts are refused', () async {
      proxy.mode = ProxyMode.down;
      await expectLater(device.login(adminEmail, 'WrongPass123', 'admin'), throwsA(isA<ApiException>().having((e) => e.message, 'message', 'Invalid email or password')));
      await expectLater(device.login(staffEmail, staffPassword, 'admin'), throwsA(isA<ApiException>().having((e) => e.message, 'message', contains('registered as staff'))));
      await expectLater(device.login('stranger@example.com', staffPassword, 'admin'), throwsA(isA<ApiException>().having((e) => e.message, 'message', contains('sign in once'))));
    });

    test('five wrong passwords lock the account, even for the right password', () async {
      proxy.mode = ProxyMode.down;
      for (var i = 0; i < AuthRepository.maxFailedAttempts; i++) {
        await expectLater(device.login(staffEmail, 'nope-nope-1', 'staff'), throwsA(isA<ApiException>()));
      }
      await expectLater(device.login(staffEmail, staffPassword, 'staff'), throwsA(isA<ApiException>().having((e) => e.message, 'message', contains('Too many'))));

      final account = (await device.tokens.offlineAccount(staffEmail))!;
      await device.tokens.saveOfflineAccount(staffEmail, account.copyWith(clearLock: true));
      expect((await device.login(staffEmail, staffPassword, 'staff')).role, 'staff');
    });

    test('offline access expires if the server has not seen the account for 30 days', () async {
      final account = (await device.tokens.offlineAccount(adminEmail))!;
      await device.tokens.saveOfflineAccount(adminEmail, account.copyWith(verifiedAt: DateTime.now().subtract(const Duration(days: 31))));
      proxy.mode = ProxyMode.down;
      await expectLater(device.login(adminEmail, staffPassword, 'admin'), throwsA(isA<ApiException>().having((e) => e.message, 'message', contains('expired'))));
      proxy.mode = ProxyMode.up;
      await device.login(adminEmail, staffPassword, 'admin'); // restores it
    });

    test('a password the server rejects stops working offline too', () async {
      final temp = await owner.dio.post('/auth/staff', data: {'name': 'Temp', 'email': 'temp@example.com', 'password': staffPassword, 'role': 'staff'});
      await device.login('temp@example.com', staffPassword, 'staff');
      await device.logout();
      await owner.dio.delete('/users/${temp.data['user']['_id']}');
      await expectLater(device.login('temp@example.com', staffPassword, 'staff'), throwsA(isA<ApiException>()));
      proxy.mode = ProxyMode.down;
      await expectLater(device.login('temp@example.com', staffPassword, 'staff'), throwsA(isA<ApiException>().having((e) => e.message, 'message', contains('sign in once'))));
    });

    test('a connection lost during token refresh does not end the session', () async {
      await device.login(adminEmail, staffPassword, 'admin');
      await device.tokens.updateAccessToken('expired-token');
      // The API answers the 401, then the network dies before the refresh.
      final stale = ApiClient(device.tokens, baseUrl: proxyUrl);
      stale.dio.interceptors.insert(0, InterceptorsWrapper(onError: (e, h) {
        proxy.mode = ProxyMode.down;
        h.next(e);
      }));
      await expectLater(AuthApi(stale).me(), throwsA(isA<ApiException>()));
      expect(await device.tokens.refreshToken, isNotNull);
      expect(await device.tokens.offlineAccount(adminEmail), isNotNull);
      proxy.mode = ProxyMode.up;
      expect((await AuthApi(device.client).me()).email, adminEmail);
    });
  });

  group('offline operation', () {
    setUpAll(() async {
      await device.login(adminEmail, staffPassword, 'admin');
      await device.sync.syncNow();
      expect(device.sync.status, SyncStatus.idle);
      pen = productFromCache((await device.db.allProducts()).firstWhere((p) => p.sku == 'STN-00002'));
    });

    test('status goes offline when the server is gone, with Wi-Fi still up', () async {
      proxy.mode = ProxyMode.down;
      await device.sync.syncNow();
      expect(device.sync.status, SyncStatus.offline);
    });

    test('a full offline day reaches the server exactly as it happened', () async {
      proxy.mode = ProxyMode.down;
      await device.sync.syncNow();

      // Add a product with a photo, while offline.
      final added = await device.inventory.create({
        'name': 'Offline Ruler', 'category': 'stationery', 'price': 50.0, 'reorderThreshold': 3,
        'isMadeToOrder': false, 'isAvailableOnline': true, 'barcode': '5550001', 'description': 'Steel', 'currentStock': 10,
      }, image: pngBytes, imageName: 'ruler.png');
      expect(added.queued, isTrue);
      expect(added.product.sku, startsWith('NEW-'));
      expect(isLocalProductId(added.product.id), isTrue);

      // It's immediately usable: visible in stock, sellable, editable.
      expect((await device.inventory.list()).map((p) => p.name), contains('Offline Ruler'));
      await device.inventory.update(added.product, {'price': 60.0});
      final ruler = await device.cached(added.product.id);
      expect(ruler.price, 60);

      // Stock takes in a delivery, and something else gets removed.
      final penBefore = (await device.cached(pen.id)).currentStock;
      expect(await device.inventory.adjustStock(pen, delta: 7, reason: 'Delivery'), isTrue);
      final rice = productFromCache((await device.db.allProducts()).firstWhere((p) => p.sku == 'GRO-00001'));
      expect(await device.inventory.update(rice, {'price': 1500.0}).then((r) => r.queued), isTrue);
      final football = productFromCache((await device.db.allProducts()).firstWhere((p) => p.sku == 'SPT-00001'));
      expect(await device.inventory.delete(football), isTrue);

      // Sales: an existing product and the one created offline.
      final saleTime = DateTime.now();
      expect((await device.sell(pen, 2)).outcome, SaleRecordOutcome.queuedOffline);
      expect((await device.sell(ruler, 3, payment: 'card')).outcome, SaleRecordOutcome.queuedOffline);
      expect((await device.cached(pen.id)).currentStock, penBefore + 7 - 2);
      expect((await device.cached(ruler.id)).currentStock, 7);

      // More than is on the shelf is refused locally, like the server would.
      await expectLater(device.sell(ruler, 100), throwsA(isA<ApiException>().having((e) => e.message, 'message', contains('Insufficient stock'))));

      // Today's records work with no server.
      final today = DateTime.now();
      final local = await device.db.localSalesInRange(DateTime(today.year, today.month, today.day), today);
      final offlineSales = local.where((s) => s.pendingSync).toList();
      expect(offlineSales.length, 2);
      final row = summariseByDay(offlineSales).single;
      expect(row.revenue, 2 * pen.price + 3 * 60);
      expect(row.cash, 2 * pen.price);
      expect(row.card, 180);
      expect(row.notSynced, 2);
      final stock = buildStockRecord(offlineSales, await device.inventory.list());
      expect(stock.firstWhere((r) => r.name == 'Offline Ruler').soldQty, 3);
      expect(stock.firstWhere((r) => r.name == 'Offline Ruler').remaining, 7);

      // Back online.
      proxy.mode = ProxyMode.up;
      await Future<void>.delayed(const Duration(seconds: 1)); // sold-at differs from sync time
      await device.sync.syncNow();
      expect(device.sync.status, SyncStatus.idle, reason: device.sync.lastError);
      expect(await device.db.allPendingOps(), isEmpty);
      expect((await device.db.unsyncedSales()), isEmpty);

      // Everything is really on the server.
      final onServer = (await owner.productsNamed('Offline Ruler')).single as Map<String, dynamic>;
      expect(onServer['sku'], matches(RegExp(r'^STN-\d{5}$')));
      expect(onServer['price'], 60);
      expect(onServer['currentStock'], 7);
      expect(onServer['barcode'], '5550001');
      expect(onServer['imageUrl'], startsWith('https://res.cloudinary.com/'), reason: 'the offline photo uploads on sync');
      expect((await owner.product(pen.id))['currentStock'], penBefore + 7 - 2);
      expect((await owner.product(rice.id))['price'], 1500);
      expect((await owner.product(football.id))['isActive'], isFalse);

      final sales = (await owner.sales()).where((s) => s['recordedOffline'] == true).toList();
      final rulerSale = sales.firstWhere((s) => (s['items'] as List).first['name'] == 'Offline Ruler');
      expect(rulerSale['paymentMethod'], 'card');
      expect(rulerSale['total'], 180);
      expect(rulerSale['cashier']['name'], 'Ayesha Admin');
      final soldAt = DateTime.parse(rulerSale['createdAt'] as String);
      expect(soldAt.difference(saleTime).inSeconds.abs(), lessThan(2), reason: 'dated when sold, not when synced');

      // The device swaps its temporary ids and placeholders for the real ones.
      expect(await device.db.productById(added.product.id), isNull);
      final real = await device.cached(onServer['_id'] as String);
      expect(real.sku, onServer['sku']);
      expect(real.imageUrl, onServer['imageUrl']);
      final confirmed = await device.db.localSalesInRange(saleTime.subtract(const Duration(minutes: 1)), DateTime.now());
      expect(confirmed.where((s) => s.pendingSync), isEmpty);
      expect(confirmed.map((s) => s.invoiceNumber), isNot(contains('PENDING')));
      expect(confirmed.expand((s) => s.items).map((i) => i.productId), contains(real.id));

      // Screens still holding the old id keep working.
      final edited = await device.inventory.update(added.product, {'price': 65.0});
      expect(edited.queued, isFalse);
      expect((await owner.product(real.id))['price'], 65);
    });

    test('nothing is applied twice when the reply to a push is lost', () async {
      proxy.mode = ProxyMode.down;
      await device.sync.syncNow();
      final stockBefore = (await device.cached(pen.id)).currentStock;
      final salesBefore = (await owner.sales()).length;
      final added = await device.inventory.create({
        'name': 'Lost Reply Item', 'category': 'stationery', 'price': 10.0, 'reorderThreshold': 1,
        'isMadeToOrder': false, 'isAvailableOnline': true, 'barcode': '', 'description': '', 'currentStock': 4,
      });
      await device.inventory.adjustStock(pen, delta: 3, reason: 'Recount');
      await device.sell(pen, 1);

      proxy.mode = ProxyMode.dropResponses;
      await device.sync.syncNow();
      expect(await device.db.allPendingOps(), isNotEmpty, reason: 'the device must assume it failed');

      proxy.mode = ProxyMode.up;
      await device.sync.syncNow();
      await device.sync.syncNow();
      expect(device.sync.status, SyncStatus.idle, reason: device.sync.lastError);
      expect(await owner.productsNamed('Lost Reply Item'), hasLength(1));
      expect(await device.db.productById(added.product.id), isNull);
      expect((await owner.product(pen.id))['currentStock'], stockBefore + 3 - 1);
      expect((await owner.sales()).length, salesBefore + 1);
    });

    test('API up with a dead database: sales fall back to the queue', () async {
      await device.sync.syncNow();
      proxy.mode = ProxyMode.serverError;
      expect((await device.sell(pen, 1)).outcome, SaleRecordOutcome.queuedOffline);
      proxy.mode = ProxyMode.up;
      await device.sync.syncNow();
      expect(await device.db.unsyncedSales(), isEmpty);
    });

    test('photo storage failing never holds up sales, and the photo is kept', () async {
      // A stand-in for the real failure: the upload is refused downstream.
      await device.sync.syncNow();
      final item = (await device.inventory.create({
        'name': 'Photo Later', 'category': 'stationery', 'price': 10.0, 'reorderThreshold': 1,
        'isMadeToOrder': false, 'isAvailableOnline': true, 'barcode': '', 'description': '', 'currentStock': 4,
      })).product;
      await device.db.queueOp(opId: 'op-photo-test', type: 'product_image', productId: item.id, label: 'Photo for Photo Later', imageBytes: Uint8List.fromList(utf8.encode('not an image')), imageName: 'x.txt');
      proxy.mode = ProxyMode.down;
      await device.sync.syncNow();
      await device.sell(item, 1);
      proxy.mode = ProxyMode.up;
      await device.sync.syncNow();

      expect(device.sync.status, SyncStatus.idle, reason: device.sync.lastError);
      expect(await device.db.unsyncedSales(), isEmpty, reason: 'the sale still went through');
      final op = (await device.db.allPendingOps()).single;
      expect(op.lastError, contains('Only JPG, PNG, or WEBP'));
      await device.db.removeOp(op.seq);
    });

    group('a sale the server rejects', () {
      late Product scarce;

      setUp(() async {
        await device.sync.syncNow();
        scarce = (await device.inventory.create({
          'name': 'Scarce ${DateTime.now().microsecondsSinceEpoch}', 'category': 'stationery', 'price': 100.0, 'reorderThreshold': 0,
          'isMadeToOrder': false, 'isAvailableOnline': true, 'barcode': '', 'description': '', 'currentStock': 2,
        })).product;
        await device.sync.syncNow();

        // Sold offline here while another till sells the same stock online.
        proxy.mode = ProxyMode.down;
        await device.sync.syncNow();
        await device.sell(scarce, 2);
        await owner.dio.post('/sales', data: {'clientTxnId': 'other-till-${scarce.id}', 'items': [{'product': scarce.id, 'quantity': 2}], 'paymentMethod': 'cash'});
        proxy.mode = ProxyMode.up;
        await device.sync.syncNow();
      });

      test('is kept with its reason and not retried automatically', () async {
        expect(device.sync.status, SyncStatus.idle, reason: 'other work keeps syncing');
        final queued = (await device.db.unsyncedSales()).single;
        expect(queued.syncError, contains('Insufficient stock'));

        final before = (await owner.sales()).length;
        await device.sync.syncNow();
        expect((await owner.sales()).length, before);
        await device.db.discardSale(queued);
      });

      test('goes through on retry once the stock is corrected', () async {
        final queued = (await device.db.unsyncedSales()).single;
        await device.inventory.adjustStock(scarce, delta: 2, reason: 'Found on shelf');
        await device.db.retrySale(queued.clientTxnId);
        await device.sync.syncNow();
        expect(await device.db.unsyncedSales(), isEmpty);
      });

      test('can be discarded, which puts the local stock back', () async {
        final queued = (await device.db.unsyncedSales()).single;
        final before = (await device.cached(scarce.id)).currentStock;
        await device.db.discardSale(queued);
        expect((await device.cached(scarce.id)).currentStock, before + 2);
        expect(await device.db.unsyncedSales(), isEmpty);
        expect(await device.db.localSalesInRange(DateTime(2000), DateTime.now()).then((s) => s.where((x) => x.clientTxnId == queued.clientTxnId)), isEmpty);
      });
    });

    test('a discarded product change is undone by the next sync', () async {
      proxy.mode = ProxyMode.down;
      await device.sync.syncNow();
      final current = await device.cached(pen.id);
      await device.inventory.update(current, {'price': 999.0});
      await device.db.discardOp((await device.db.allPendingOps()).single);
      proxy.mode = ProxyMode.up;
      await device.sync.syncNow();
      expect((await device.cached(pen.id)).price, current.price);
    });

    test('a shared device keeps each person\'s sales credited to them', () async {
      await device.sync.syncNow();
      proxy.mode = ProxyMode.down;
      await device.sync.syncNow();
      await device.logout();
      await device.login(staffEmail, staffPassword, 'staff');
      final current = await device.cached(pen.id);
      await device.sell(current, 1);
      await device.logout();
      await device.login(adminEmail, staffPassword, 'admin');
      await device.sell(current, 1);

      // The admin syncs: both reach the server, under the right names.
      proxy.mode = ProxyMode.up;
      await device.sync.syncNow();
      expect(await device.db.unsyncedSales(), isEmpty);
      final latest = (await owner.sales()).take(2).toList();
      expect(latest.map((s) => s['cashier']['_id']), contains(staffId));
      expect(latest.map((s) => s['cashier']['name']), containsAll(['Bilal Staff', 'Ayesha Admin']));
    });

    test('staff only push their own queue; admin product changes wait for an admin', () async {
      await device.sync.syncNow();
      proxy.mode = ProxyMode.down;
      await device.sync.syncNow();
      final current = await device.cached(pen.id);
      await device.inventory.update(current, {'description': 'Queued by admin'});
      await device.sell(current, 1); // admin's sale
      await device.logout();

      await device.login(staffEmail, staffPassword, 'staff');
      proxy.mode = ProxyMode.up;
      await device.sync.syncNow();
      expect(device.sync.status, SyncStatus.idle, reason: device.sync.lastError);
      expect(await device.db.unsyncedSales(), hasLength(1));
      expect(await device.db.allPendingOps(), hasLength(1));

      await device.logout();
      await device.login(adminEmail, staffPassword, 'admin');
      await device.sync.syncNow();
      expect(await device.db.unsyncedSales(), isEmpty);
      expect(await device.db.allPendingOps(), isEmpty);
      expect((await owner.product(pen.id))['description'], 'Queued by admin');
    });

    test('nothing syncs after logout', () async {
      final before = (await owner.sales()).length;
      proxy.mode = ProxyMode.down;
      await device.sync.syncNow();
      await device.sell(await device.cached(pen.id), 1);
      await device.logout();
      proxy.mode = ProxyMode.up;
      await device.sync.syncNow();
      expect((await owner.sales()).length, before);
      await device.login(adminEmail, staffPassword, 'admin');
      await device.sync.syncNow();
      expect((await owner.sales()).length, before + 1);
    });
  });

  group('month of records', () {
    test('every sale of a busy month reaches the device, past the API page size', () async {
      await device.login(adminEmail, staffPassword, 'admin');
      await owner.dio.post('/products/${pen.id}/adjust-stock', data: {'delta': 300, 'reason': 'Bulk'});
      final pushes = [
        for (var day = 0; day < 15; day++)
          owner.dio.post('/sync/push', data: {
            'sales': [
              for (var n = 0; n < 15; n++)
                {
                  'clientTxnId': 'history-$day-$n',
                  'items': [{'product': pen.id, 'quantity': 1}],
                  'paymentMethod': 'cash',
                  'soldAt': DateTime.now().subtract(Duration(days: day + 1)).toUtc().toIso8601String(),
                },
            ],
          }),
      ];
      for (final push in pushes) {
        await push;
      }
      final fresh = Device(AppDatabase(NativeDatabase.memory()));
      fresh.user = device.user;
      await fresh.sync.pullRecentSales();
      final sales = await fresh.db.localSalesInRange(DateTime.now().subtract(const Duration(days: 31)), DateTime.now());
      expect(sales.where((s) => s.clientTxnId.startsWith('history-')), hasLength(225));
      final byDay = summariseByDay(sales.where((s) => s.clientTxnId.startsWith('history-')));
      expect(byDay.length, greaterThanOrEqualTo(15));
      expect(byDay.every((r) => r.notSynced == 0), isTrue);
      await fresh.db.close();
    });

    test('old confirmed records are pruned, unsynced ones never are', () async {
      Sale old(String id, DateTime at) => Sale(
            id: id, clientTxnId: id, invoiceNumber: 'INV-$id', items: const [], subtotal: 1, taxAmount: 0,
            total: 1, paymentMethod: 'cash', createdAt: at, recordedOffline: false,
          );
      final longAgo = DateTime.now().subtract(const Duration(days: 60));
      await device.db.upsertLocalSale(old('old-confirmed', longAgo));
      await device.db.upsertLocalSale(old('old-unsynced', longAgo), pending: true);
      await device.db.pruneRecords(DateTime.now().subtract(const Duration(days: 35)));
      final left = await device.db.localSalesInRange(DateTime(2000), DateTime.now().subtract(const Duration(days: 35)));
      expect(left.map((s) => s.clientTxnId), ['old-unsynced']);
      await device.db.discardSale(QueuedSale(clientTxnId: 'old-unsynced', items: [], paymentMethod: 'cash', createdAt: longAgo));
    });
  });
}

