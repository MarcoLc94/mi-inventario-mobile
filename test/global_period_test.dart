import 'package:flutter_test/flutter_test.dart';
import 'package:mi_inventario_mobile/features/cfdis/global_invoice_new_screen.dart';

void main() {
  final today = DateTime(2026, 10, 16);

  test('daily and monthly periods', () {
    expect(periodRange('01', '2026-10-10', null, '1', today), (start: '2026-10-10', end: '2026-10-10'));
    expect(periodRange('04', null, DateTime(2026, 2), '1', today), (start: '2026-02-01', end: '2026-02-28'));
  });

  test('weekly periods never cross the month or go past today', () {
    expect(periodRange('02', '2026-09-28', null, '1', today), (start: '2026-09-28', end: '2026-09-30'));
    expect(periodRange('02', '2026-10-14', null, '1', today), (start: '2026-10-14', end: '2026-10-16'));
  });

  test('fortnights and bimesters', () {
    expect(periodRange('03', null, DateTime(2026, 9), '1', today), (start: '2026-09-01', end: '2026-09-15'));
    expect(periodRange('03', null, DateTime(2026, 9), '2', today), (start: '2026-09-16', end: '2026-09-30'));
    expect(periodRange('05', null, DateTime(2026, 4), '1', today), (start: '2026-03-01', end: '2026-04-30'));
  });
}
