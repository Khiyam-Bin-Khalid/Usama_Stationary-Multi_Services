import 'package:intl/intl.dart';

final _currencyFormat = NumberFormat.currency(locale: 'en_PK', symbol: 'Rs. ', decimalDigits: 0);

String formatCurrency(num value) => _currencyFormat.format(value);

final _dateFormat = DateFormat('d MMM yyyy, h:mm a');
String formatDateTime(DateTime dt) => _dateFormat.format(dt.toLocal());

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
