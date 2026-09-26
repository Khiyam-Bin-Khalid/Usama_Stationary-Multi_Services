class OrderItemView {
  final String productId;
  final String name;
  final String category;
  final double unitPrice;
  final num quantity;
  final double lineTotal;

  const OrderItemView({
    required this.productId,
    required this.name,
    required this.category,
    required this.unitPrice,
    required this.quantity,
    required this.lineTotal,
  });

  factory OrderItemView.fromJson(Map<String, dynamic> json) => OrderItemView(
        productId: json['product'] as String,
        name: json['name'] as String,
        category: json['category'] as String,
        unitPrice: (json['unitPrice'] as num).toDouble(),
        quantity: json['quantity'] as num,
        lineTotal: (json['lineTotal'] as num).toDouble(),
      );
}

class CustomerOrder {
  final String id;
  final String orderNumber;
  final List<OrderItemView> items;
  final double subtotal;
  final double discountTotal;
  final double taxAmount;
  final double deliveryFee;
  final double total;
  final String paymentMethod;
  final String paymentStatus;
  final String status;
  final DateTime createdAt;
  final Map<String, dynamic>? delivery;

  const CustomerOrder({
    required this.id,
    required this.orderNumber,
    required this.items,
    required this.subtotal,
    required this.discountTotal,
    required this.taxAmount,
    required this.deliveryFee,
    required this.total,
    required this.paymentMethod,
    required this.paymentStatus,
    required this.status,
    required this.createdAt,
    this.delivery,
  });

  factory CustomerOrder.fromJson(Map<String, dynamic> json) => CustomerOrder(
        id: json['_id'] as String,
        orderNumber: json['orderNumber'] as String,
        items: (json['items'] as List).map((e) => OrderItemView.fromJson(e as Map<String, dynamic>)).toList(),
        subtotal: (json['subtotal'] as num).toDouble(),
        discountTotal: (json['discountTotal'] as num?)?.toDouble() ?? 0,
        taxAmount: (json['taxAmount'] as num?)?.toDouble() ?? 0,
        deliveryFee: (json['deliveryFee'] as num?)?.toDouble() ?? 0,
        total: (json['total'] as num).toDouble(),
        paymentMethod: json['paymentMethod'] as String,
        paymentStatus: json['paymentStatus'] as String,
        status: json['status'] as String,
        createdAt: DateTime.parse(json['createdAt'] as String),
        delivery: json['delivery'] as Map<String, dynamic>?,
      );
}
