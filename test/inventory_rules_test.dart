import 'package:flutter_test/flutter_test.dart';
import 'package:mi_inventario_mobile/core/catalogs.dart';
import 'package:mi_inventario_mobile/core/ids.dart';

void main() {
  test('units accept quantities with their allowed decimals, like the web', () {
    const kg = Unit(code: 'kg', name: 'Kilogramo', plural: 'Kilogramos', symbol: 'kg', decimals: 3);
    expect(Unit.piece.accepts(3), isTrue);
    expect(Unit.piece.accepts(2.5), isFalse);
    expect(Unit.piece.accepts(0), isFalse);
    expect(Unit.piece.accepts(0, allowZero: true), isTrue);
    expect(Unit.piece.accepts(-1, allowZero: true), isFalse);
    expect(kg.accepts(1.255), isTrue);
    expect(kg.accepts(1.2555), isFalse);
    expect(kg.precisionMessage, contains('3 decimales'));
    expect(Unit.piece.precisionMessage, contains('enteras'));
  });

  test('unit catalog entries parse from the API', () {
    final unit = Unit.fromJson({'code': 'l', 'name': 'Litro', 'plural': 'Litros', 'symbol': 'L', 'decimals': 3});
    expect(unit.symbol, 'L');
    expect(unit.decimals, 3);
  });

  test('request keys are unique v4 UUIDs', () {
    final a = newRequestKey();
    final b = newRequestKey();
    expect(a, isNot(b));
    expect(RegExp(r'^[0-9a-f]{8}-[0-9a-f]{4}-4[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$').hasMatch(a), isTrue);
  });
}
