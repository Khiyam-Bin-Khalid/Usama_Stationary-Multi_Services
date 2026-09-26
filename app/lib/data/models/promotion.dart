class Promotion {
  final String id;
  final String name;
  final String? description;
  final String discountType; // 'percent' | 'flat'
  final double discountValue;
  final List<String> categories;
  final DateTime startDate;
  final DateTime endDate;

  const Promotion({
    required this.id,
    required this.name,
    this.description,
    required this.discountType,
    required this.discountValue,
    required this.categories,
    required this.startDate,
    required this.endDate,
  });

  factory Promotion.fromJson(Map<String, dynamic> json) => Promotion(
        id: json['_id'] as String,
        name: json['name'] as String,
        description: json['description'] as String?,
        discountType: json['discountType'] as String,
        discountValue: (json['discountValue'] as num).toDouble(),
        categories: (json['categories'] as List? ?? []).map((e) => e as String).toList(),
        startDate: DateTime.parse(json['startDate'] as String),
        endDate: DateTime.parse(json['endDate'] as String),
      );

  String get discountLabel => discountType == 'percent' ? '${discountValue.toStringAsFixed(0)}% off' : 'Rs. $discountValue off';
}
