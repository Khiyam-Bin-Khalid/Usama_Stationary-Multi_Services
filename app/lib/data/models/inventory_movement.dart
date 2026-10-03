/// One row of the stock-movement history (GET /inventory/movements).
class InventoryMovement {
  final String id;
  final String productId;
  final String productName;
  final String? sku;
  final String? barcode;
  final String? imageUrl;
  final String? unit;
  final String? category;
  final String type;
  final int? previousStock;
  final num quantityDelta;
  final num resultingStock;
  final String? reference;
  final String? reason;
  final String? actorName;
  final String? actorRole;
  final DateTime createdAt;

  const InventoryMovement({
    required this.id,
    required this.productId,
    required this.productName,
    this.sku,
    this.barcode,
    this.imageUrl,
    this.unit,
    this.category,
    required this.type,
    this.previousStock,
    required this.quantityDelta,
    required this.resultingStock,
    this.reference,
    this.reason,
    this.actorName,
    this.actorRole,
    required this.createdAt,
  });

  factory InventoryMovement.fromJson(Map<String, dynamic> json) {
    final product = json['product'];
    final productMap = product is Map ? product : null;
    final actor = json['actor'];
    final actorMap = actor is Map ? actor : null;
    return InventoryMovement(
      id: json['_id'] as String,
      productId: productMap != null ? productMap['_id'] as String : product as String,
      productName: json['productName'] as String? ?? productMap?['name'] as String? ?? 'Product',
      sku: json['sku'] as String? ?? productMap?['sku'] as String?,
      barcode: productMap?['barcode'] as String?,
      imageUrl: productMap?['imageUrl'] as String?,
      unit: productMap?['unit'] as String?,
      category: json['category'] as String?,
      type: json['type'] as String,
      previousStock: (json['previousStock'] as num?)?.toInt(),
      quantityDelta: json['quantityDelta'] as num,
      resultingStock: json['resultingStock'] as num,
      reference: json['reference'] as String?,
      reason: json['reason'] as String?,
      actorName: actorMap?['name'] as String?,
      actorRole: actorMap?['role'] as String?,
      createdAt: DateTime.parse(json['createdAt'] as String),
    );
  }
}
