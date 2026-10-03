/// One ordered line. Carries the snapshot taken when the order was placed —
/// name, SKU, image reference, unit price — so the item the customer chose is
/// shown identically through the whole lifecycle (cart → checkout → review →
/// processing → delivery → history), regardless of later catalog edits.
class OrderItemView {
  final String productId;
  final String name;
  final String? sku;
  final String? barcode;
  final String? imageUrl;
  final String category;
  final double unitPrice;
  final num quantity;
  final double lineTotal;

  const OrderItemView({
    required this.productId,
    required this.name,
    this.sku,
    this.barcode,
    this.imageUrl,
    required this.category,
    required this.unitPrice,
    required this.quantity,
    required this.lineTotal,
  });

  factory OrderItemView.fromJson(Map<String, dynamic> json) => OrderItemView(
        productId: json['product'] is Map ? (json['product'] as Map)['_id'] as String : json['product'] as String,
        name: json['name'] as String,
        sku: json['sku'] as String?,
        barcode: json['barcode'] as String?,
        imageUrl: json['imageUrl'] as String?,
        category: json['category'] as String,
        unitPrice: (json['unitPrice'] as num).toDouble(),
        quantity: json['quantity'] as num,
        lineTotal: (json['lineTotal'] as num).toDouble(),
      );
}

/// Priced cart returned by POST /orders/quote — the checkout summary.
class OrderQuote {
  final List<OrderItemView> items;
  final double subtotal;
  final double discountTotal;
  final String? promotionName;
  final double taxRate;
  final double taxAmount;
  final double deliveryFee;
  final double total;

  const OrderQuote({
    required this.items,
    required this.subtotal,
    required this.discountTotal,
    this.promotionName,
    required this.taxRate,
    required this.taxAmount,
    required this.deliveryFee,
    required this.total,
  });

  factory OrderQuote.fromJson(Map<String, dynamic> json) => OrderQuote(
        items: (json['items'] as List).map((e) => OrderItemView.fromJson(e as Map<String, dynamic>)).toList(),
        subtotal: (json['subtotal'] as num).toDouble(),
        discountTotal: (json['discountTotal'] as num?)?.toDouble() ?? 0,
        promotionName: json['promotion'] is Map ? (json['promotion'] as Map)['name'] as String? : null,
        taxRate: (json['taxRate'] as num?)?.toDouble() ?? 0,
        taxAmount: (json['taxAmount'] as num?)?.toDouble() ?? 0,
        deliveryFee: (json['deliveryFee'] as num?)?.toDouble() ?? 0,
        total: (json['total'] as num).toDouble(),
      );
}

class OrderStatusEvent {
  final String status;
  final DateTime at;
  final String? note;
  final String? byName;

  const OrderStatusEvent({required this.status, required this.at, this.note, this.byName});

  factory OrderStatusEvent.fromJson(Map<String, dynamic> json) => OrderStatusEvent(
        status: json['status'] as String,
        at: DateTime.parse(json['at'] as String),
        note: json['note'] as String?,
        byName: json['by'] is Map ? (json['by'] as Map)['name'] as String? : null,
      );
}

/// Payment record attached to an order (receipt upload + admin review).
class OrderPayment {
  final String id;
  final String method;
  final String status;
  final double amount;
  final String? receiptImageUrl;
  final String? receiptNote;
  final DateTime? receiptUploadedAt;
  final String? reviewedByName;
  final DateTime? reviewedAt;
  final String? reviewNote;

  const OrderPayment({
    required this.id,
    required this.method,
    required this.status,
    required this.amount,
    this.receiptImageUrl,
    this.receiptNote,
    this.receiptUploadedAt,
    this.reviewedByName,
    this.reviewedAt,
    this.reviewNote,
  });

  bool get hasReceipt => receiptImageUrl != null && receiptImageUrl!.isNotEmpty;

  factory OrderPayment.fromJson(Map<String, dynamic> json) => OrderPayment(
        id: json['_id'] as String,
        method: json['method'] as String,
        status: json['status'] as String,
        amount: (json['amount'] as num?)?.toDouble() ?? 0,
        receiptImageUrl: json['receiptImageUrl'] as String?,
        receiptNote: json['receiptNote'] as String?,
        receiptUploadedAt: json['receiptUploadedAt'] != null ? DateTime.parse(json['receiptUploadedAt'] as String) : null,
        reviewedByName: json['reviewedBy'] is Map ? (json['reviewedBy'] as Map)['name'] as String? : null,
        reviewedAt: json['reviewedAt'] != null ? DateTime.parse(json['reviewedAt'] as String) : null,
        reviewNote: json['reviewNote'] as String?,
      );
}

class OrderCustomer {
  final String? id;
  final String name;
  final String? email;
  final String? phone;
  const OrderCustomer({this.id, required this.name, this.email, this.phone});

  static OrderCustomer? fromJson(dynamic json) {
    if (json is! Map) return null;
    return OrderCustomer(
      id: json['_id'] as String?,
      name: json['name'] as String? ?? 'Customer',
      email: json['email'] as String?,
      phone: json['phone'] as String?,
    );
  }
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
  final List<OrderStatusEvent> statusHistory;
  final OrderPayment? payment;
  final OrderCustomer? customer;

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
    this.statusHistory = const [],
    this.payment,
    this.customer,
  });

  int get itemCount => items.fold(0, (sum, i) => sum + i.quantity.toInt());

  Map<String, dynamic>? get address => delivery?['address'] is Map ? Map<String, dynamic>.from(delivery!['address'] as Map) : null;
  String get addressLine {
    final a = address;
    if (a == null) return '';
    return [a['line1'], a['line2'], a['city']].where((p) => p != null && '$p'.isNotEmpty).join(', ');
  }

  String? get courierName => delivery?['courierName'] as String?;
  String? get trackingNote => delivery?['trackingNote'] as String?;
  String? get deliveryWindow => delivery?['window'] as String?;

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
        delivery: json['delivery'] is Map ? Map<String, dynamic>.from(json['delivery'] as Map) : null,
        statusHistory: (json['statusHistory'] as List? ?? const [])
            .map((e) => OrderStatusEvent.fromJson(Map<String, dynamic>.from(e as Map)))
            .toList(),
        payment: json['payment'] is Map ? OrderPayment.fromJson(Map<String, dynamic>.from(json['payment'] as Map)) : null,
        customer: OrderCustomer.fromJson(json['customer']),
      );
}
