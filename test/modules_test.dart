import 'package:flutter_test/flutter_test.dart';
import 'package:mi_inventario_mobile/core/modules.dart';
import 'package:mi_inventario_mobile/core/user_profile.dart';

UserProfile user(Map<String, dynamic> raw) => UserProfile(raw);
List<String> titles(List<MenuEntry> entries) => [for (final e in entries) e.divider ? '---' : e.title!];

void main() {
  test('a basic user without invoicing sees locked paid modules and no admin', () {
    final entries = visibleModules(user({'role': 'user', 'account_enabled_modules': ['inventory']}));
    expect(titles(entries), isNot(contains('Backoffice')));
    expect(titles(entries), isNot(contains('Administración')));
    final compras = entries.firstWhere((e) => e.title == 'Compras');
    expect(compras.locked, isTrue);
    expect(compras.path, integrationsPath);
    expect(compras.items, isNull);
    // Sin Facturación, Proveedores aparece dentro de Inventario.
    final inventario = entries.firstWhere((e) => e.title == 'Inventario');
    expect(inventario.items!.map((i) => i.path), contains('/suppliers'));
  });

  test('admin with invoicing but no sale invoice permission only sees fiscal settings in CFDIs', () {
    final entries = visibleModules(user({'role': 'admin', 'account_invoicing_active': true}));
    final cfdis = entries.firstWhere((e) => e.title == 'CFDIs');
    expect(cfdis.locked, isFalse);
    expect(cfdis.items!.map((i) => i.path), ['/cfdis/configuracion']);
    expect(titles(entries), contains('Administración'));
    final inventario = entries.firstWhere((e) => e.title == 'Inventario');
    expect(inventario.items!.map((i) => i.path), isNot(contains('/suppliers')));
  });

  test('non-admin with invoicing and no invoice permission does not see CFDIs', () {
    final entries = visibleModules(user({'role': 'user', 'account_invoicing_active': true}));
    expect(titles(entries), isNot(contains('CFDIs')));
  });

  test('point of sale needs the module and read permission', () {
    MenuEntry pos(Map<String, dynamic> raw) => visibleModules(user(raw)).firstWhere((e) => e.title == 'Punto de venta');
    expect(pos({'account_pos_active': true}).locked, isTrue);
    expect(pos({'account_pos_active': true, 'pos_permission': {'read': true}}).locked, isFalse);
  });

  test('backoffice only with permission and no dangling dividers', () {
    final entries = visibleModules(user({'role': 'user', 'backoffice_permission': true}));
    expect(titles(entries).first, 'Backoffice');
    expect(entries.last.divider, isFalse);
  });
}
