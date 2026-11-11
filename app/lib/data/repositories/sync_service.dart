import 'dart:async';
import 'dart:convert';
import 'package:connectivity_plus/connectivity_plus.dart';
import '../../core/roles.dart';
import '../local/app_database.dart';
import '../models/sale.dart';
import '../models/user.dart';
import '../remote/api_client.dart';
import '../remote/product_api.dart';
import '../remote/promotion_api.dart';
import '../remote/sale_api.dart';
import '../remote/sync_api.dart';
import '../remote/token_storage.dart';

/// Keeps the local drift cache (products/promotions/sales) fresh and drains
/// the offline queues whenever the server is reachable. It retries on a timer
/// as well as on connectivity changes: "Wi-Fi is up" says nothing about whether
/// the server is, so the timer is what notices a server coming back.
///
/// Each sync runs, in order:
///  1. Product changes ([PendingOps]), one at a time, so sales of a product
///     created offline can use the id the server gives it.
///  2. Queued sales ([PendingSales]). A sale the server rejects is set aside
///     with its reason for an Admin to resolve, and not retried automatically.
///  3. Queued product photos. Last, because a photo failure (e.g. image storage
///     refusing uploads) must not hold up sales.
///  4. Pull: catalog/promotion deltas, today's sales, and periodically the full
///     month of dated records.
class SyncService {
  final AppDatabase db;
  final ProductApi productApi;
  final PromotionApi promotionApi;
  final SyncApi syncApi;
  final SaleApi saleApi;
  final TokenStorage tokenStorage;
  final AppUser? Function() currentUser;
  final Duration retryInterval;

  static const _backfillEvery = Duration(hours: 1);

  /// Records older than this are removed locally. A few days past
  /// [AppDatabase.recordDays], so the oldest shown day is always complete.
  static const _pruneAfter = Duration(days: AppDatabase.recordDays + 4);

  StreamSubscription<List<ConnectivityResult>>? _connectivitySub;
  Timer? _retryTimer;
  bool _syncing = false;
  DateTime? _lastBackfill;

  final _statusController = StreamController<SyncStatus>.broadcast();
  Stream<SyncStatus> get statusStream => _statusController.stream;
  SyncStatus _status = SyncStatus.syncing;

  /// The latest status, for widgets that subscribe after it was announced.
  SyncStatus get status => _status;
  bool get isOffline => _status == SyncStatus.offline;

  /// Why the last sync stopped, when [status] is [SyncStatus.error].
  String? lastError;

  final _changesController = StreamController<int>.broadcast();
  int _revision = 0;

  /// Ticks whenever a sync changed what's on the server, so screens that read
  /// the API (rather than watching the local DB) know to reload.
  Stream<int> get changes => _changesController.stream;

  SyncService({
    required this.db,
    required this.productApi,
    required this.promotionApi,
    required this.syncApi,
    required this.saleApi,
    required this.tokenStorage,
    required this.currentUser,
    this.retryInterval = const Duration(seconds: 30),
  });

  void start() {
    _connectivitySub = Connectivity().onConnectivityChanged.listen((results) {
      final isOnline = results.any((r) => r != ConnectivityResult.none);
      if (isOnline) syncNow();
    });
    _retryTimer = Timer.periodic(retryInterval, (_) => syncNow());
    syncNow();
  }

  void dispose() {
    _connectivitySub?.cancel();
    _retryTimer?.cancel();
    _statusController.close();
    _changesController.close();
  }

  void _setStatus(SyncStatus status) {
    _status = status;
    if (!_statusController.isClosed) _statusController.add(status);
  }

  /// [retryFailedPhotos] also resends photos that failed earlier, which
  /// otherwise only happens with the hourly backfill: they're large.
  Future<void> syncNow({bool retryFailedPhotos = false}) async {
    if (_syncing || currentUser() == null || await tokenStorage.isLoggedOut) return;
    _syncing = true;
    // While offline, keep saying so until a sync actually succeeds, instead of
    // flickering the banner on every background retry.
    if (!isOffline) _setStatus(SyncStatus.syncing);
    try {
      final now = DateTime.now();
      final backfillDue = _lastBackfill == null || now.difference(_lastBackfill!) >= _backfillEvery;
      final pushed = await pushQueuedOps() + await pushQueuedSales() + await pushQueuedPhotos(includeFailed: retryFailedPhotos || backfillDue);
      await pullCatalog();
      await pullTodaySales();
      if (backfillDue) {
        await pullRecentSales();
        await db.pruneRecords(now.subtract(_pruneAfter));
        _lastBackfill = now;
      }
      lastError = null;
      _setStatus(SyncStatus.idle);
      if (pushed > 0 && !_changesController.isClosed) _changesController.add(++_revision);
    } on ApiException catch (e) {
      if (e.isServerDown) {
        _setStatus(SyncStatus.offline);
      } else if (e.statusCode == 401) {
        _setStatus(SyncStatus.authRequired);
      } else {
        lastError = e.toString();
        _setStatus(SyncStatus.error);
      }
    } catch (e) {
      lastError = e.toString();
      _setStatus(SyncStatus.error);
    } finally {
      _syncing = false;
    }
  }

  bool get _isAdmin {
    final role = currentUser()?.role;
    return role != null && Permissions.editInventory(role);
  }

  // ── Push: product changes ─────────────────────────────────────────────────

  /// Returns how many changes reached the server. Stops at the first sign the
  /// server is down (keeping the order); a rejected change is set aside and
  /// anything depending on it waits with it.
  Future<int> pushQueuedOps() async {
    if (!_isAdmin) return 0; // staff can't apply these; the next Admin will
    var pushed = 0;
    final seqs = (await db.allPendingOps()).where((o) => o.type != 'product_image').map((o) => o.seq).toList();
    for (final seq in seqs) {
      // Re-read: a create earlier in this loop may have repointed this op.
      final op = await db.pendingOpBySeq(seq);
      if (op == null || op.lastError != null) continue;
      final isCreate = op.type == 'product_create';
      if (!isCreate && isLocalProductId(op.productId!)) continue;
      try {
        final result = await syncApi.applyOp(
          opId: op.opId,
          type: op.type,
          productId: isCreate ? null : op.productId,
          payload: jsonDecode(op.payloadJson) as Map<String, dynamic>,
        );
        final product = result['product'] as Map<String, dynamic>?;
        if (isCreate) {
          await db.remapProductId(op.productId!, productCompanionFromJson(product!));
        } else if (product != null) {
          await db.upsertProduct(productCompanionFromJson(product));
        }
        await db.removeOp(seq);
        pushed++;
      } on ApiException catch (e) {
        if (e.isServerDown || e.statusCode == 401) rethrow;
        await db.markOpError(seq, e.toString());
      }
    }
    return pushed;
  }

  // ── Push: upload queued offline sales ─────────────────────────────────────

  static const _maxSalesPerPush = 200; // server limit

  Future<int> pushQueuedSales() async {
    final user = currentUser();
    if (user == null) return 0;
    final isStaff = user.role == UserRole.staff;
    final queued = (await db.unsyncedSales())
        .where((s) => s.syncError == null && !s.waitsForProduct)
        // Staff can only vouch for their own sales; an Admin or the cashier
        // themselves will push the others.
        .where((s) => !isStaff || s.cashierId == null || s.cashierId == user.id)
        .toList();

    var pushed = 0;
    for (var start = 0; start < queued.length; start += _maxSalesPerPush) {
      final batch = queued.skip(start).take(_maxSalesPerPush);
      final results = await syncApi.pushSales(batch.map(_salePayload).toList());
      for (final result in results) {
        final clientTxnId = result['clientTxnId'] as String;
        if (result['status'] == 'ok') {
          pushed++;
          await db.markSynced(clientTxnId);
          final saleData = result['sale'] as Map<String, dynamic>?;
          if (saleData == null) {
            await db.markLocalSaleConfirmed(clientTxnId);
          } else {
            // Swaps the PENDING placeholder for the real invoice number.
            await db.confirmLocalSale(clientTxnId, Sale.fromJson(saleData));
          }
        } else {
          await db.markSyncError(clientTxnId, result['error']?.toString() ?? 'Unknown error');
        }
      }
    }
    return pushed;
  }

  static Map<String, dynamic> _salePayload(QueuedSale s) => {
        'clientTxnId': s.clientTxnId,
        'items': [
          for (final item in s.items) {'product': item['productId'] ?? item['product'], 'quantity': item['quantity']},
        ],
        'paymentMethod': s.paymentMethod,
        'recordedOffline': true,
        'soldAt': s.createdAt.toUtc().toIso8601String(),
        if (s.cashierId != null) 'cashierId': s.cashierId,
      };

  // ── Push: product photos ──────────────────────────────────────────────────

  Future<int> pushQueuedPhotos({required bool includeFailed}) async {
    if (!_isAdmin) return 0;
    var pushed = 0;
    for (final op in (await db.allPendingOps()).where((o) => o.type == 'product_image')) {
      if (isLocalProductId(op.productId!) || (op.lastError != null && !includeFailed)) continue;
      try {
        final product = await productApi.uploadImage(op.productId!, op.imageBytes!, op.imageName ?? 'product.jpg');
        await db.upsertProduct(productCompanionFromJson(product.toJson()));
        await db.removeOp(op.seq);
        pushed++;
      } on ApiException catch (e) {
        if (e.isNetworkError || e.statusCode == 401) rethrow;
        await db.markOpError(op.seq, e.toString());
      }
    }
    return pushed;
  }

  // ── Pull: catalog deltas from server ──────────────────────────────────────

  Future<void> pullCatalog() async {
    final since = await db.lastSyncTime();
    final data = await syncApi.pullDeltas(since);

    final products = (data['products'] as List).cast<Map<String, dynamic>>();
    if (products.isNotEmpty) {
      await db.replaceProducts(products.map(productCompanionFromJson).toList());
    }

    final promotions = (data['promotions'] as List).cast<Map<String, dynamic>>();
    if (promotions.isNotEmpty) {
      await db.replacePromotions(
        promotions.map(_promotionToCompanion).toList(),
      );
    }

    await db.setLastSyncTime(DateTime.parse(data['serverTime'] as String));
  }

  // ── Pull: sales from other devices / the admin portal ─────────────────────

  /// Today's sales, on every sync, so the Daily Sale tab stays current.
  Future<void> pullTodaySales() async {
    final now = DateTime.now();
    await _saveSales(await saleApi.listSales(from: DateTime(now.year, now.month, now.day), to: now));
  }

  /// The whole month of dated records. Also picks up offline sales another
  /// device pushed late, which belong to past days the daily pull doesn't see.
  Future<void> pullRecentSales() async {
    final now = DateTime.now();
    await _saveSales(await saleApi.listAllSales(from: now.subtract(const Duration(days: AppDatabase.recordDays)), to: now));
  }

  Future<void> _saveSales(List<Sale> sales) async {
    for (final sale in sales) {
      await db.upsertLocalSale(sale); // pending = false (server-confirmed)
    }
  }

  // ── Companions ─────────────────────────────────────────────────────────────

  PromotionsCacheCompanion _promotionToCompanion(Map<String, dynamic> p) =>
      PromotionsCacheCompanion.insert(
        id: p['_id'] as String,
        name: p['name'] as String,
        discountType: p['discountType'] as String,
        discountValue: (p['discountValue'] as num).toDouble(),
        categoriesJson: (p['categories'] as List? ?? []).join(','),
        startDate: DateTime.parse(p['startDate'] as String),
        endDate: DateTime.parse(p['endDate'] as String),
      );
}

enum SyncStatus { idle, syncing, offline, authRequired, error }
