import 'package:intl/intl.dart';

final _number = NumberFormat.decimalPattern('es_MX')..maximumFractionDigits = 2;
final _money = NumberFormat.currency(locale: 'es_MX', symbol: r'$');
final _date = DateFormat('d MMM yyyy', 'es_MX');
final _dateTime = DateFormat('d MMM yyyy, HH:mm', 'es_MX');

/// La API manda cantidades como número o como texto (BigDecimal).
num? toNum(dynamic value) {
  if (value == null) return null;
  if (value is num) return value;
  return num.tryParse(value.toString().trim());
}

String formatNumber(dynamic value) {
  final n = toNum(value);
  return n == null ? '—' : _number.format(n);
}

String formatMoney(dynamic value) {
  final n = toNum(value);
  return n == null ? '—' : _money.format(n);
}

DateTime? parseDate(dynamic value) => value == null ? null : DateTime.tryParse(value.toString())?.toLocal();

String formatDate(dynamic value) {
  final d = parseDate(value);
  return d == null ? 'Sin fecha' : _date.format(d);
}

String formatDateTime(dynamic value) {
  final d = parseDate(value);
  return d == null ? 'Sin registro' : _dateTime.format(d);
}
