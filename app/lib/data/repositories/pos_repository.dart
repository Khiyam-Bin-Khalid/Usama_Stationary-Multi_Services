import 'package:uuid/uuid.dart';
import '../local/app_database.dart';
import '../models/cart_item.dart';
import '../models/sale.dart';
import '../remote/api_client.dart';
import '../remote/sale_api.dart';

enum SaleRecordOutcome { syncedOnline, queuedOffline }

class SaleRecordResult {
  final SaleRecordOutcome outcome;
  final String clientTxnId;
  const SaleRecordResult(this.outcome, this.clientTxnId);
}

/// POS checkout: try to record the sale online immediately; if the request
/// fails for network reasons, queue it in the local drift DB instead of
/// losing it. Either way, stock is decremented in the local cache right
/// away so the cashier's next sale sees accurate numbers.
///
/// In both outcomes, the sale is written to [LocalSalesCache] so the
/// "Daily Sale" tab and daily records can show it while offline.
class PosRepository {
  // Null on web: the storefront/admin-web build has no local SQLite cache
  // (see connection_web.dart), so there's nowhere to queue an offline sale —
  // web callers just surface the network error instead.
  final AppDatabase? db;
  final SaleApi saleApi;

  /// True while sync knows the server is unreachable: go straight to the local
  /// queue rather than making the cashier wait out a connection timeout.
  final bool Function() isOffline;
  final _uuid = const Uuid();

  PosRepository({required this.db, required this.saleApi, bool Function()? isOffline})
      : isOffline = isOffline ?? (() => false);

  Future<SaleRecordResult> recordSale({
    required List<CartItem> items,
    required String paymentMethod,
    String? cashierId,
    String? cashierName,
  }) async {
    final local = db;
    final clientTxnId = 'pos-${_uuid.v4()}';
    final soldAt = DateTime.now();
    if (local == null) {
      await saleApi.recordSale(clientTxnId: clientTxnId, items: _serverItems(items), paymentMethod: paymentMethod);
      return SaleRecordResult(SaleRecordOutcome.syncedOnline, clientTxnId);
    }

    // A cart can outlive a sync, so resolve products created offline first.
    final lines = [for (final item in items) (await local.resolveProductId(item.product.id), item)];
    final queue = lines.any((l) => isLocalProductId(l.$1)) || isOffline();
    if (queue) return _queueSale(local, clientTxnId, soldAt, lines, paymentMethod, cashierId, cashierName);

    try {
      final responseData = await saleApi.recordSale(
        clientTxnId: clientTxnId,
        items: [for (final (id, item) in lines) {'product': id, 'quantity': item.quantity}],
        paymentMethod: paymentMethod,
      );
      for (final (id, item) in lines) {
        await local.applyLocalStockDelta(id, -item.quantity);
      }
      // Cache the confirmed sale for the offline Daily Sale view.
      try {
        await local.upsertLocalSale(Sale.fromJson(responseData['sale'] as Map<String, dynamic>));
      } catch (_) {
        // The sale itself succeeded; the next sync brings the cached copy in.
      }
      return SaleRecordResult(SaleRecordOutcome.syncedOnline, clientTxnId);
    } on ApiException catch (e) {
      if (!e.isServerDown) rethrow; // a real rejection, e.g. out of stock
      return _queueSale(local, clientTxnId, soldAt, lines, paymentMethod, cashierId, cashierName);
    }
  }

  static List<Map<String, dynamic>> _serverItems(List<CartItem> items) =>
      [for (final i in items) {'product': i.product.id, 'quantity': i.quantity}];

  Future<SaleRecordResult> _queueSale(
    AppDatabase local,
    String clientTxnId,
    DateTime soldAt,
    List<(String, CartItem)> lines,
    String paymentMethod,
    String? cashierId,
    String? cashierName,
  ) async {
    // The server can't check stock offline, so hold the same line locally.
    for (final (id, item) in lines) {
      final row = await local.productById(id);
      if (row != null && !row.isMadeToOrder && row.currentStock < item.quantity) {
        throw ApiException('Insufficient stock for ${row.name} (have ${row.currentStock}, need ${item.quantity})');
      }
    }
    await local.transaction(() async {
      for (final (id, item) in lines) {
        await local.applyLocalStockDelta(id, -item.quantity);
      }
      await local.queueSale(
        clientTxnId: clientTxnId,
        items: [
          for (final (id, item) in lines)
            {'productId': id, 'quantity': item.quantity, 'name': item.product.name, 'unitPrice': item.product.price},
        ],
        paymentMethod: paymentMethod,
        createdAt: soldAt,
        cashierId: cashierId,
        cashierName: cashierName,
      );
      // Pending in the local sales cache, so it shows in the Daily Sale tab
      // and daily records straight away.
      await local.upsertLocalSale(
        _buildPendingSale(clientTxnId, soldAt, lines, paymentMethod, cashierId, cashierName),
        pending: true,
      );
    });
    return SaleRecordResult(SaleRecordOutcome.queuedOffline, clientTxnId);
  }

  /// Construct a [Sale] from cart data for immediate local storage when the
  /// device is offline. The invoice number is a placeholder until the server
  /// confirms the sale.
  static Sale _buildPendingSale(
    String clientTxnId,
    DateTime soldAt,
    List<(String, CartItem)> lines,
    String paymentMethod,
    String? cashierId,
    String? cashierName,
  ) {
    final lineItems = [
      for (final (id, item) in lines)
        SaleLineItem(
          productId: id,
          name: item.product.name,
          sku: item.product.sku,
          imageUrl: item.product.imageUrl,
          category: item.product.category,
          unitPrice: item.product.price,
          quantity: item.quantity.toDouble(),
          lineTotal: item.product.price * item.quantity,
        ),
    ];
    final total = lineItems.fold(0.0, (s, i) => s + i.lineTotal);
    return Sale(
      id: clientTxnId,
      clientTxnId: clientTxnId,
      invoiceNumber: 'PENDING',
      items: lineItems,
      subtotal: total,
      taxAmount: 0,
      total: total,
      paymentMethod: paymentMethod,
      createdAt: soldAt,
      recordedOffline: true,
      cashierId: cashierId,
      cashierName: cashierName,
    );
  }
}
