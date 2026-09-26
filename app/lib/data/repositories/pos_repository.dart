import 'package:uuid/uuid.dart';
import '../local/app_database.dart';
import '../remote/api_client.dart';
import '../remote/sale_api.dart';
import '../models/cart_item.dart';

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
      await saleApi.recordSale(
        clientTxnId: clientTxnId,
        items: items.map((i) => {'product': i.product.id, 'quantity': i.quantity}).toList(),
        paymentMethod: paymentMethod,
      );
      if (db != null) {
        for (final item in items) {
          await db!.applyLocalStockDelta(item.product.id, -item.quantity);
        }
      }
      return SaleRecordResult(SaleRecordOutcome.syncedOnline, clientTxnId);
    } on ApiException catch (e) {
      if (!e.isNetworkError || db == null) rethrow; // real rejection, or no local queue to fall back to
      for (final item in items) {
        await db!.applyLocalStockDelta(item.product.id, -item.quantity);
      }
      await db!.queueSale(clientTxnId: clientTxnId, items: itemPayload, paymentMethod: paymentMethod);
      return SaleRecordResult(SaleRecordOutcome.queuedOffline, clientTxnId);
    }
  }
}
