class DiscrepancyReport {
  final String id;
  final String productId;
  final String productName;
  final String category;
  final int systemQty;
  final int countedQty;
  final String? note;
  final String status;
  final String? reportedByName;
  final String? resolvedByName;
  final String? resolution;
  final int? adjustmentApplied;
  final DateTime createdAt;

  const DiscrepancyReport({
    required this.id,
    required this.productId,
    required this.productName,
    required this.category,
    required this.systemQty,
    required this.countedQty,
    this.note,
    required this.status,
    this.reportedByName,
    this.resolvedByName,
    this.resolution,
    this.adjustmentApplied,
    required this.createdAt,
  });

  int get difference => countedQty - systemQty;
  bool get isOpen => status == 'open';

  factory DiscrepancyReport.fromJson(Map<String, dynamic> json) {
    String? nameOf(dynamic v) => v is Map ? v['name'] as String? : null;
    final product = json['product'];
    return DiscrepancyReport(
      id: json['_id'] as String,
      productId: product is Map ? product['_id'] as String : product as String,
      productName: json['productName'] as String,
      category: json['category'] as String,
      systemQty: (json['systemQty'] as num).toInt(),
      countedQty: (json['countedQty'] as num).toInt(),
      note: json['note'] as String?,
      status: json['status'] as String,
      reportedByName: nameOf(json['reportedBy']),
      resolvedByName: nameOf(json['resolvedBy']),
      resolution: json['resolution'] as String?,
      adjustmentApplied: (json['adjustmentApplied'] as num?)?.toInt(),
      createdAt: DateTime.parse(json['createdAt'] as String),
    );
  }
}
