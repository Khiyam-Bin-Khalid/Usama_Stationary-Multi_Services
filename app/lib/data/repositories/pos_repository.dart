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
/// "Daily Sale" tab can show it even when the device is offline.
class PosRepository {
  // Null on web: the storefront/admin-web build has no local SQLite cache
  // (see connection_web.dart), so there's nowhere to queue an offline sale —
  // web callers just surface the network error instead.
  final AppDatabase? db;
  final SaleApi saleApi;
  final _uuid = const Uuid();

  PosRepository({required this.db, required this.saleApi});

  Future<SaleRecordResult> recordSale({
    required List<CartItem> items,
    required String paymentMethod,
    String? cashierName,
  }) async {
    final clientTxnId = 'pos-${_uuid.v4()}';
    final itemPayload = items
        .map((i) => {
              'productId': i.product.id,
              'quantity': i.quantity,
              'name': i.product.name,
              'unitPrice': i.product.price,
            })
        .toList();

    try {
      final responseData = await saleApi.recordSale(
        clientTxnId: clientTxnId,
        items: items
            .map((i) => {'product': i.product.id, 'quantity': i.quantity})
            .toList(),
        paymentMethod: paymentMethod,
      );

      if (db != null) {
        for (final item in items) {
          await db!.applyLocalStockDelta(item.product.id, -item.quantity);
        }
        // Cache the confirmed sale for the offline Daily Sale view.
        final saleData = responseData['sale'] as Map<String, dynamic>?;
        if (saleData != null) {
          try {
            await db!.upsertLocalSale(Sale.fromJson(saleData));
          } catch (_) {
            // Best-effort — a cache write failure must not break the sale.
          }
        } else {
          // Server didn't return the full sale body — store a local stub so
          // the Daily Sale tab still shows the transaction.
          await db!.upsertLocalSale(
            _buildPendingSale(clientTxnId, items, paymentMethod, cashierName),
            pending: false,
          );
        }
      }
      return SaleRecordResult(SaleRecordOutcome.syncedOnline, clientTxnId);
    } on ApiException catch (e) {
      if (!e.isNetworkError || db == null) {
        rethrow; // real rejection, or no local queue to fall back to
      }
      for (final item in items) {
        await db!.applyLocalStockDelta(item.product.id, -item.quantity);
      }
      await db!.queueSale(
        clientTxnId: clientTxnId,
        items: itemPayload,
        paymentMethod: paymentMethod,
      );
      // Store as pending in the local sales cache so it appears in the
      // Daily Sale tab immediately even before syncing to the server.
      await db!.upsertLocalSale(
        _buildPendingSale(clientTxnId, items, paymentMethod, cashierName),
        pending: true,
      );
      return SaleRecordResult(SaleRecordOutcome.queuedOffline, clientTxnId);
    }
  }

  /// Construct a [Sale] from cart data for immediate local storage when the
  /// device is offline. The invoice number is a placeholder until the server
  /// confirms the sale.
  static Sale _buildPendingSale(
    String clientTxnId,
    List<CartItem> items,
    String paymentMethod,
    String? cashierName,
  ) {
    final now = DateTime.now();
    final lineItems = items
        .map((i) => SaleLineItem(
              productId: i.product.id,
              name: i.product.name,
              sku: i.product.sku,
              imageUrl: i.product.imageUrl,
              category: i.product.category,
              unitPrice: i.product.price,
              quantity: i.quantity.toDouble(),
              lineTotal: i.product.price * i.quantity,
            ))
        .toList();
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
      createdAt: now,
      recordedOffline: true,
      cashierName: cashierName,
    );
  }
}
