import 'dart:async';
import 'package:connectivity_plus/connectivity_plus.dart';
import '../local/app_database.dart';
import '../remote/product_api.dart';
import '../remote/promotion_api.dart';
import '../remote/sync_api.dart';

/// Keeps the local drift cache (products/promotions) fresh and drains the
/// offline sales queue whenever connectivity returns. This is what lets the
/// POS screen keep working through a short network interruption (SRS NFR:
/// Availability) and reconcile everything once the connection is back.
class SyncService {
  final AppDatabase db;
  final ProductApi productApi;
  final PromotionApi promotionApi;
  final SyncApi syncApi;

  StreamSubscription<List<ConnectivityResult>>? _connectivitySub;
  bool _syncing = false;

  final _statusController = StreamController<SyncStatus>.broadcast();
  Stream<SyncStatus> get statusStream => _statusController.stream;

  SyncService({
    required this.db,
    required this.productApi,
    required this.promotionApi,
    required this.syncApi,
  });

  void start() {
    _connectivitySub = Connectivity().onConnectivityChanged.listen((results) {
      final isOnline = results.any((r) => r != ConnectivityResult.none);
      if (isOnline) syncNow();
    });
    syncNow();
  }

  void dispose() {
    _connectivitySub?.cancel();
    _statusController.close();
  }

  Future<void> syncNow() async {
    if (_syncing) return;
    _syncing = true;
    _statusController.add(SyncStatus.syncing);
    try {
      await pushQueuedSales();
      await pullCatalog();
      _statusController.add(SyncStatus.idle);
    } catch (_) {
      // Offline or server unreachable — normal condition, not an error the
      // user needs to see; the POS screen keeps serving from local cache.
      _statusController.add(SyncStatus.offline);
    } finally {
      _syncing = false;
    }
  }

  Future<void> pushQueuedSales() async {
    final queued = await db.unsyncedSales();
    if (queued.isEmpty) return;

    final results = await syncApi.pushSales(queued
        .map((s) => {
              'clientTxnId': s.clientTxnId,
              'items': s.items,
              'paymentMethod': s.paymentMethod,
              'recordedOffline': true,
            })
        .toList());

    for (final result in results) {
      final clientTxnId = result['clientTxnId'] as String;
      if (result['status'] == 'ok') {
        await db.markSynced(clientTxnId);
      } else {
        await db.markSyncError(clientTxnId, result['error']?.toString() ?? 'Unknown error');
      }
    }
  }

  Future<void> pullCatalog() async {
    final since = await db.lastSyncTime();
    final data = await syncApi.pullDeltas(since);

    final products = (data['products'] as List).cast<Map<String, dynamic>>();
    if (products.isNotEmpty) {
      await db.replaceProducts(products.map((p) => _productToCompanion(p)).toList());
    }

    final promotions = (data['promotions'] as List).cast<Map<String, dynamic>>();
    if (promotions.isNotEmpty) {
      await db.replacePromotions(promotions.map((p) => _promotionToCompanion(p)).toList());
    }

    await db.setLastSyncTime(DateTime.parse(data['serverTime'] as String));
  }

  ProductsCacheCompanion _productToCompanion(Map<String, dynamic> p) => ProductsCacheCompanion.insert(
        id: p['_id'] as String,
        name: p['name'] as String,
        sku: p['sku'] as String,
        category: p['category'] as String,
        unit: p['unit'] as String? ?? 'pcs',
        price: (p['price'] as num).toDouble(),
        costPrice: (p['costPrice'] as num?)?.toDouble() ?? 0,
        currentStock: (p['currentStock'] as num?)?.toInt() ?? 0,
        reorderThreshold: (p['reorderThreshold'] as num?)?.toInt() ?? 0,
        isMadeToOrder: p['isMadeToOrder'] as bool? ?? false,
        isAvailableOnline: p['isAvailableOnline'] as bool? ?? true,
        isActive: p['isActive'] as bool? ?? true,
        updatedAt: DateTime.parse(p['updatedAt'] as String),
      );

  PromotionsCacheCompanion _promotionToCompanion(Map<String, dynamic> p) => PromotionsCacheCompanion.insert(
        id: p['_id'] as String,
        name: p['name'] as String,
        discountType: p['discountType'] as String,
        discountValue: (p['discountValue'] as num).toDouble(),
        categoriesJson: (p['categories'] as List? ?? []).join(','),
        startDate: DateTime.parse(p['startDate'] as String),
        endDate: DateTime.parse(p['endDate'] as String),
      );
}

enum SyncStatus { idle, syncing, offline }
