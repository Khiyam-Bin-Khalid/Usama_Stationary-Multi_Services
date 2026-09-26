class SaleItemInput {
  final String productId;
  final num quantity;
  const SaleItemInput({required this.productId, required this.quantity});

  Map<String, dynamic> toJson() => {'product': productId, 'quantity': quantity};
}

class Sale {
  final String id;
  final String clientTxnId;
  final String invoiceNumber;
  final double subtotal;
  final double taxAmount;
  final double total;
  final String paymentMethod;
  final DateTime createdAt;
  final bool recordedOffline;

  const Sale({
    required this.id,
    required this.clientTxnId,
    required this.invoiceNumber,
    required this.subtotal,
    required this.taxAmount,
    required this.total,
    required this.paymentMethod,
    required this.createdAt,
    required this.recordedOffline,
  });

  factory Sale.fromJson(Map<String, dynamic> json) => Sale(
        id: json['_id'] as String,
        clientTxnId: json['clientTxnId'] as String,
        invoiceNumber: json['invoiceNumber'] as String,
        subtotal: (json['subtotal'] as num).toDouble(),
        taxAmount: (json['taxAmount'] as num).toDouble(),
        total: (json['total'] as num).toDouble(),
        paymentMethod: json['paymentMethod'] as String,
        createdAt: DateTime.parse(json['createdAt'] as String),
        recordedOffline: json['recordedOffline'] as bool? ?? false,
      );
}
