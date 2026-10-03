class Product {
  final String id;
  final String name;
  /// System-generated business identifier (e.g. STN-00001). Distinct from the
  /// database [id] and from the physical [barcode].
  final String sku;
  final String? barcode;
  final String category;
  final String unit;
  final double price;
  final double costPrice;
  final int currentStock;
  final int reorderThreshold;
  final bool isMadeToOrder;
  final bool isAvailableOnline;
  final bool isActive;
  final String? imageUrl;
  final String? description;
  final String? createdByName;
  final String? createdByRole;

  const Product({
    required this.id,
    required this.name,
    required this.sku,
    this.barcode,
    required this.category,
    required this.unit,
    required this.price,
    required this.costPrice,
    required this.currentStock,
    required this.reorderThreshold,
    required this.isMadeToOrder,
    required this.isAvailableOnline,
    required this.isActive,
    this.imageUrl,
    this.description,
    this.createdByName,
    this.createdByRole,
  });

  bool get isOutOfStock => !isMadeToOrder && currentStock <= 0;
  bool get isLowStock => !isMadeToOrder && currentStock > 0 && currentStock <= reorderThreshold;
  /// Spec §4.1: out-of-stock products are hidden from POS quick-sell + storefront.
  bool get isSellable => isActive && !isOutOfStock;

  factory Product.fromJson(Map<String, dynamic> json) => Product(
        id: json['_id'] as String,
        name: json['name'] as String,
        sku: json['sku'] as String,
        barcode: json['barcode'] as String?,
        category: json['category'] as String,
        unit: json['unit'] as String? ?? 'pcs',
        price: (json['price'] as num).toDouble(),
        costPrice: (json['costPrice'] as num?)?.toDouble() ?? 0,
        currentStock: (json['currentStock'] as num?)?.toInt() ?? 0,
        reorderThreshold: (json['reorderThreshold'] as num?)?.toInt() ?? 0,
        isMadeToOrder: json['isMadeToOrder'] as bool? ?? false,
        isAvailableOnline: json['isAvailableOnline'] as bool? ?? true,
        isActive: json['isActive'] as bool? ?? true,
        imageUrl: json['imageUrl'] as String?,
        description: json['description'] as String?,
        createdByName: json['createdBy'] is Map ? (json['createdBy'] as Map)['name'] as String? : null,
        createdByRole: json['createdBy'] is Map ? (json['createdBy'] as Map)['role'] as String? : null,
      );

  Map<String, dynamic> toJson() => {
        '_id': id,
        'name': name,
        'sku': sku,
        'barcode': barcode,
        'category': category,
        'unit': unit,
        'price': price,
        'costPrice': costPrice,
        'currentStock': currentStock,
        'reorderThreshold': reorderThreshold,
        'isMadeToOrder': isMadeToOrder,
        'isAvailableOnline': isAvailableOnline,
        'isActive': isActive,
        'imageUrl': imageUrl,
        'description': description,
      };
}
