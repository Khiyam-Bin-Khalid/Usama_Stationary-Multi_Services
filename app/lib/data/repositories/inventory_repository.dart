import 'dart:typed_data';
import 'package:drift/drift.dart' show Value;
import 'package:uuid/uuid.dart';
import '../local/app_database.dart';
import '../models/product.dart';
import '../remote/api_client.dart';
import '../remote/product_api.dart';

Product productFromCache(ProductsCacheData row) => Product(
      id: row.id,
      name: row.name,
      sku: row.sku,
      barcode: row.barcode,
      imageUrl: row.imageUrl,
      description: row.description,
      category: row.category,
      unit: row.unit,
      price: row.price,
      costPrice: row.costPrice,
      currentStock: row.currentStock,
      reorderThreshold: row.reorderThreshold,
      isMadeToOrder: row.isMadeToOrder,
      isAvailableOnline: row.isAvailableOnline,
      isActive: row.isActive,
    );

class ProductSaveResult {
  final Product product;

  /// Saved on this device only; goes to the server on the next sync.
  final bool queued;

  /// Set when the product saved but its photo did not reach image storage.
  final String? imageWarning;

  const ProductSaveResult(this.product, {this.queued = false, this.imageWarning});
}

/// Product and stock management for Admin / Super Admin. Writes go straight to
/// the server when it's reachable. When it isn't, the change is applied to the
/// local catalog and queued in [PendingOps] for SyncService to replay in order,
/// so the same screen works online and offline.
class InventoryRepository {
  final AppDatabase? db; // null on web, which has no local store
  final ProductApi api;
  final bool Function() isOffline;
  final _uuid = const Uuid();

  InventoryRepository({required this.db, required this.api, bool Function()? isOffline})
      : isOffline = isOffline ?? (() => false);

  /// Runs [online], or [offline] when the server can't be reached. Real
  /// rejections (duplicate barcode, validation) still surface to the caller.
  Future<T> _withFallback<T>(String id, Future<T> Function(String id) online, Future<T> Function(AppDatabase, String id) offline) async {
    final local = db;
    if (local == null) return online(id);
    final resolved = await local.resolveProductId(id);
    if (isOffline() || isLocalProductId(resolved)) return offline(local, resolved);
    try {
      return await online(resolved);
    } on ApiException catch (e) {
      if (!e.isServerDown) rethrow;
      return offline(local, resolved);
    }
  }

  Future<List<Product>> list() async {
    final local = db;
    if (local == null) return api.list();
    Future<List<Product>> cached() async => (await local.activeProducts()).map(productFromCache).toList();
    // Anything still queued is only reflected in the local copy.
    if (isOffline() || (await local.allPendingOps()).isNotEmpty) return cached();
    try {
      return await api.list();
    } on ApiException catch (e) {
      if (!e.isServerDown) rethrow;
      return cached();
    }
  }

  Future<ProductSaveResult> create(Map<String, dynamic> payload, {Uint8List? image, String? imageName}) async {
    final local = db;
    Future<ProductSaveResult> onlineCreate() async {
      final product = await api.create(payload);
      await _mirror(product);
      return _attachImage(product, image, imageName);
    }

    if (local == null) return onlineCreate();
    if (isOffline()) return _createOffline(local, payload, image, imageName);
    try {
      return await onlineCreate();
    } on ApiException catch (e) {
      if (!e.isServerDown) rethrow;
      return _createOffline(local, payload, image, imageName);
    }
  }

  Future<ProductSaveResult> _createOffline(AppDatabase local, Map<String, dynamic> payload, Uint8List? image, String? imageName) async {
    await _assertBarcodeFree(local, payload['barcode'] as String?);
    final id = newLocalProductId(_uuid.v4());
    final typedSku = (payload['sku'] as String?)?.trim().toUpperCase() ?? '';
    final product = Product.fromJson({
      ...payload,
      '_id': id,
      // A readable placeholder; the server assigns the real SKU on sync.
      'sku': typedSku.isNotEmpty ? typedSku : 'NEW-${id.substring(id.length - 6).toUpperCase()}',
      'barcode': (payload['barcode'] as String?)?.trim().isEmpty ?? true ? null : payload['barcode'],
      'costPrice': payload['costPrice'] ?? 0,
      'isActive': true,
    });
    await local.transaction(() async {
      await local.upsertProduct(productCompanionFromJson(product.toJson()));
      await local.queueOp(opId: 'op-${_uuid.v4()}', type: 'product_create', productId: id, label: 'Add ${product.name}', payload: payload);
      if (image != null) await _queueImage(local, product, image, imageName);
    });
    return ProductSaveResult(product, queued: true);
  }

  Future<ProductSaveResult> update(Product existing, Map<String, dynamic> payload, {Uint8List? image, String? imageName}) {
    return _withFallback(
      existing.id,
      (id) async {
        final product = await api.update(id, payload);
        await _mirror(product);
        return _attachImage(product, image, imageName);
      },
      (local, id) async {
        await _assertBarcodeFree(local, payload['barcode'] as String?, except: id);
        final row = await local.productById(id);
        final base = row == null ? existing : productFromCache(row);
        final json = {...base.toJson(), ...payload};
        if (json['barcode'] == '') json['barcode'] = null;
        final product = Product.fromJson(json);
        await local.transaction(() async {
          await local.upsertProduct(productCompanionFromJson(json));
          await local.queueOp(opId: 'op-${_uuid.v4()}', type: 'product_update', productId: id, label: 'Edit ${product.name}', payload: payload);
          if (image != null) await _queueImage(local, product, image, imageName);
        });
        return ProductSaveResult(product, queued: true);
      },
    );
  }

  /// Returns true if the delete was queued rather than applied on the server.
  Future<bool> delete(Product product) {
    return _withFallback(
      product.id,
      (id) async {
        await api.delete(id);
        final local = db;
        if (local != null) await _setInactive(local, id);
        return false;
      },
      (local, id) async {
        await local.transaction(() async {
          await _setInactive(local, id);
          await local.queueOp(opId: 'op-${_uuid.v4()}', type: 'product_delete', productId: id, label: 'Delete ${product.name}');
        });
        return true;
      },
    );
  }

  /// Returns true if the adjustment was queued rather than applied on the server.
  Future<bool> adjustStock(Product product, {required num delta, required String reason}) {
    return _withFallback(
      product.id,
      (id) async {
        await _mirror(await api.adjustStock(id, delta: delta, reason: reason));
        return false;
      },
      (local, id) async {
        final row = await local.productById(id);
        final current = row?.currentStock ?? product.currentStock;
        if (!product.isMadeToOrder && current + delta < 0) {
          throw ApiException('Insufficient stock for ${product.name} (have $current, need ${-delta})');
        }
        await local.transaction(() async {
          await local.applyLocalStockDelta(id, delta);
          await local.queueOp(
            opId: 'op-${_uuid.v4()}',
            type: 'stock_adjust',
            productId: id,
            label: 'Stock ${delta > 0 ? '+' : ''}$delta ${product.name}',
            payload: {'delta': delta, 'reason': reason},
          );
        });
        return true;
      },
    );
  }

  Future<ProductSaveResult> _attachImage(Product product, Uint8List? image, String? imageName) async {
    if (image == null) return ProductSaveResult(product);
    try {
      final updated = await api.uploadImage(product.id, image, imageName ?? 'product.jpg');
      await _mirror(updated);
      return ProductSaveResult(updated);
    } on ApiException catch (e) {
      // The product is saved at this point, whatever happens to the photo.
      final local = db;
      if (local == null || !e.isServerDown) {
        return ProductSaveResult(product, imageWarning: 'The product was saved, but its photo was not uploaded: ${e.message}');
      }
      await _queueImage(local, product, image, imageName, lastError: e.message);
      return ProductSaveResult(
        product,
        imageWarning: 'The product was saved, but its photo was not uploaded: ${e.message} It stays in the sync queue and will retry.',
      );
    }
  }

  Future<void> _queueImage(AppDatabase local, Product product, Uint8List image, String? imageName, {String? lastError}) => local.queueOp(
        opId: 'op-${_uuid.v4()}',
        type: 'product_image',
        productId: product.id,
        label: 'Photo for ${product.name}',
        imageBytes: image,
        imageName: imageName ?? 'product.jpg',
        lastError: lastError,
      );

  Future<void> _assertBarcodeFree(AppDatabase local, String? barcode, {String? except}) async {
    if (barcode == null || barcode.trim().isEmpty) return;
    final clash = (await local.allProducts()).where((p) => p.isActive && p.barcode == barcode.trim() && p.id != except);
    if (clash.isNotEmpty) {
      throw ApiException('Barcode $barcode is already assigned to ${clash.first.name}');
    }
  }

  Future<void> _mirror(Product product) async {
    final local = db;
    if (local != null) await local.upsertProduct(productCompanionFromJson(product.toJson()));
  }

  Future<void> _setInactive(AppDatabase local, String id) async {
    final row = await local.productById(id);
    if (row != null) await local.upsertProduct(row.toCompanion(false).copyWith(isActive: const Value(false)));
  }
}
