import 'package:intl/intl.dart';

final _currencyFormat = NumberFormat.currency(
  locale: 'en_PK',
  symbol: 'Rs. ',
  decimalDigits: 0,
);

String formatCurrency(num value) => _currencyFormat.format(value);

final _dateFormat = DateFormat('d MMM yyyy, h:mm a');
String formatDateTime(DateTime dt) => _dateFormat.format(dt.toLocal());

final _timeFormat = DateFormat('h:mm a');
String formatTime(DateTime dt) => _timeFormat.format(dt.toLocal());

final _fullDayFormat = DateFormat('EEE, d MMM yyyy');
String formatFullDay(DateTime dt) => _fullDayFormat.format(dt.toLocal());

/// Quantities are whole numbers in most cases; only show decimals when needed.
String formatQuantity(num value) => value == value.roundToDouble() ? value.toStringAsFixed(0) : value.toStringAsFixed(2);

final _dayFormat = DateFormat('d MMM');
final _monthFormat = DateFormat('MMM yyyy');
final _yearFormat = DateFormat('yyyy');

String formatPeriodLabel(DateTime dt, String period) {
  switch (period) {
    case 'monthly':
      return _monthFormat.format(dt.toLocal());
    case 'yearly':
      return _yearFormat.format(dt.toLocal());
    default:
      return _dayFormat.format(dt.toLocal());
  }
}
