class SaleItemInput {
  final String productId;
  final num quantity;
  const SaleItemInput({required this.productId, required this.quantity});

  Map<String, dynamic> toJson() => {'product': productId, 'quantity': quantity};
}

/// A line item as recorded on the sale — a snapshot of the product at sale
/// time (name/price), not a live lookup, so historical sales stay accurate
/// even if the product is later renamed, repriced, or deleted.
class SaleLineItem {
  final String productId;
  final String name;
  final String? sku;
  final String? imageUrl;
  final String category;
  final double unitPrice;
  final double quantity;
  final double lineTotal;

  const SaleLineItem({
    required this.productId,
    required this.name,
    this.sku,
    this.imageUrl,
    required this.category,
    required this.unitPrice,
    required this.quantity,
    required this.lineTotal,
  });

  factory SaleLineItem.fromJson(Map<String, dynamic> json) => SaleLineItem(
    productId: json['product'] is Map
        ? (json['product'] as Map)['_id'] as String
        : json['product'] as String,
    name: json['name'] as String,
    sku: json['sku'] as String?,
    imageUrl: json['imageUrl'] as String?,
    category: json['category'] as String,
    unitPrice: (json['unitPrice'] as num).toDouble(),
    quantity: (json['quantity'] as num).toDouble(),
    lineTotal: (json['lineTotal'] as num).toDouble(),
  );

  Map<String, dynamic> toJson() => {
    'product': productId,
    'name': name,
    'sku': sku,
    'imageUrl': imageUrl,
    'category': category,
    'unitPrice': unitPrice,
    'quantity': quantity,
    'lineTotal': lineTotal,
  };
}

class Sale {
  final String id;
  final String clientTxnId;
  final String invoiceNumber;
  final List<SaleLineItem> items;
  final double subtotal;
  final double taxAmount;
  final double total;
  final String paymentMethod;
  final DateTime createdAt;
  final bool recordedOffline;
  final String? cashierName;

  const Sale({
    required this.id,
    required this.clientTxnId,
    required this.invoiceNumber,
    required this.items,
    required this.subtotal,
    required this.taxAmount,
    required this.total,
    required this.paymentMethod,
    required this.createdAt,
    required this.recordedOffline,
    this.cashierName,
  });

  factory Sale.fromJson(Map<String, dynamic> json) => Sale(
    id: json['_id'] as String,
    clientTxnId: json['clientTxnId'] as String,
    invoiceNumber: json['invoiceNumber'] as String,
    items: (json['items'] as List? ?? [])
        .map((e) => SaleLineItem.fromJson(e as Map<String, dynamic>))
        .toList(),
    subtotal: (json['subtotal'] as num).toDouble(),
    taxAmount: (json['taxAmount'] as num).toDouble(),
    total: (json['total'] as num).toDouble(),
    paymentMethod: json['paymentMethod'] as String,
    createdAt: DateTime.parse(json['createdAt'] as String),
    recordedOffline: json['recordedOffline'] as bool? ?? false,
    cashierName: json['cashier'] is Map
        ? (json['cashier'] as Map)['name'] as String?
        : null,
  );

  Map<String, dynamic> toJson() => {
    '_id': id,
    'clientTxnId': clientTxnId,
    'invoiceNumber': invoiceNumber,
    'items': items.map((i) => i.toJson()).toList(),
    'subtotal': subtotal,
    'taxAmount': taxAmount,
    'total': total,
    'paymentMethod': paymentMethod,
    'createdAt': createdAt.toIso8601String(),
    'recordedOffline': recordedOffline,
    if (cashierName != null) 'cashier': {'name': cashierName},
  };
}
