class Shift {
  final String id;
  final String status;
  final double openingCash;
  final double? closingCashExpected;
  final double? closingCashActual;
  final double? cashVariance;
  final int salesCount;
  final double salesTotal;
  final double cashSalesTotal;
  final double cardSalesTotal;
  final DateTime openedAt;
  final DateTime? closedAt;
  final String? staffName;
  final String? note;

  const Shift({
    required this.id,
    required this.status,
    required this.openingCash,
    this.closingCashExpected,
    this.closingCashActual,
    this.cashVariance,
    required this.salesCount,
    required this.salesTotal,
    required this.cashSalesTotal,
    required this.cardSalesTotal,
    required this.openedAt,
    this.closedAt,
    this.staffName,
    this.note,
  });

  bool get isOpen => status == 'open';

  factory Shift.fromJson(Map<String, dynamic> json) {
    final staff = json['staff'];
    return Shift(
      id: json['_id'] as String,
      status: json['status'] as String,
      openingCash: (json['openingCash'] as num? ?? 0).toDouble(),
      closingCashExpected: (json['closingCashExpected'] as num?)?.toDouble(),
      closingCashActual: (json['closingCashActual'] as num?)?.toDouble(),
      cashVariance: (json['cashVariance'] as num?)?.toDouble(),
      salesCount: (json['salesCount'] as num? ?? 0).toInt(),
      salesTotal: (json['salesTotal'] as num? ?? 0).toDouble(),
      cashSalesTotal: (json['cashSalesTotal'] as num? ?? 0).toDouble(),
      cardSalesTotal: (json['cardSalesTotal'] as num? ?? 0).toDouble(),
      openedAt: DateTime.parse(json['openedAt'] as String),
      closedAt: json['closedAt'] != null ? DateTime.parse(json['closedAt'] as String) : null,
      staffName: staff is Map ? staff['name'] as String? : null,
      note: json['note'] as String?,
    );
  }
}

/// Live view of a shift: the shift document plus totals computed from the
/// sales attached to it so far (GET /shifts/current, GET /shifts/:id).
class ShiftReport {
  final Shift shift;
  final int salesCount;
  final double salesTotal;
  final double cashSalesTotal;
  final double cardSalesTotal;
  final double closingCashExpected;

  const ShiftReport({
    required this.shift,
    required this.salesCount,
    required this.salesTotal,
    required this.cashSalesTotal,
    required this.cardSalesTotal,
    required this.closingCashExpected,
  });

  factory ShiftReport.fromJson(Map<String, dynamic> json) => ShiftReport(
        shift: Shift.fromJson(json['shift'] as Map<String, dynamic>),
        salesCount: (json['salesCount'] as num? ?? 0).toInt(),
        salesTotal: (json['salesTotal'] as num? ?? 0).toDouble(),
        cashSalesTotal: (json['cashSalesTotal'] as num? ?? 0).toDouble(),
        cardSalesTotal: (json['cardSalesTotal'] as num? ?? 0).toDouble(),
        closingCashExpected: (json['closingCashExpected'] as num? ?? 0).toDouble(),
      );
}
