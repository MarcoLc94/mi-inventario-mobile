import 'package:flutter/material.dart';

import 'user_profile.dart';

/// Menú de la app: mismo contenido y reglas que la web
/// (ats-inventory-frontend/src/data/menuModules.ts → getVisibleModules).
class MenuItem {
  const MenuItem(this.path, this.icon, this.label);
  final String path;
  final IconData icon;
  final String label;
}

class MenuEntry {
  const MenuEntry({this.title, this.icon, this.path, this.items, this.divider = false, this.locked = false});
  const MenuEntry.divider([this.title])
      : icon = null,
        path = null,
        items = null,
        divider = true,
        locked = false;

  final String? title;
  final IconData? icon;
  final String? path;
  final List<MenuItem>? items;
  final bool divider;

  /// Módulo de pago sin contratar: se muestra con candado y lleva a Integraciones.
  final bool locked;

  MenuEntry copyWith({List<MenuItem>? items, bool? locked, String? path, bool clearItems = false}) => MenuEntry(
        title: title,
        icon: icon,
        path: path ?? this.path,
        items: clearItems ? null : (items ?? this.items),
        locked: locked ?? this.locked,
      );
}

const integrationsPath = '/account-settings?section=integraciones';

const allModules = <MenuEntry>[
  MenuEntry(title: 'Backoffice', icon: Icons.admin_panel_settings, path: '/platform-admin'),
  MenuEntry(title: 'Inicio', icon: Icons.home_outlined, path: '/'),
  MenuEntry(title: 'Inventario', icon: Icons.inventory_outlined, items: [
    MenuItem('/products', Icons.inventory_2_outlined, 'Productos'),
    MenuItem('/categories', Icons.category_outlined, 'Categorías'),
    MenuItem('/inventory-adjustments', Icons.tune, 'Ajustes de inventario'),
    MenuItem('/transfers', Icons.swap_horiz, 'Transferencias'),
    MenuItem('/inventory/lots', Icons.event_busy_outlined, 'Lotes y caducidades'),
    MenuItem('/stock-history', Icons.swap_vert, 'Movimientos'),
    MenuItem('/inventory/receipts', Icons.receipt_long_outlined, 'Comprobantes'),
  ]),
  MenuEntry(title: 'Punto de venta', icon: Icons.point_of_sale_outlined, items: [
    MenuItem('/pos', Icons.point_of_sale_outlined, 'Cobrar'),
    MenuItem('/pos/tickets', Icons.confirmation_number_outlined, 'Tickets'),
    MenuItem('/pos/cortes', Icons.fact_check_outlined, 'Cortes'),
  ]),
  MenuEntry.divider('Facturación'),
  MenuEntry(title: 'Compras', icon: Icons.local_shipping_outlined, items: [
    MenuItem('/suppliers', Icons.local_shipping_outlined, 'Proveedores'),
    MenuItem('/suppliers/orders', Icons.shopping_cart_outlined, 'Órdenes de compra'),
    MenuItem('/suppliers/returns', Icons.keyboard_return, 'Devoluciones proveedor'),
  ]),
  MenuEntry(title: 'Ventas', icon: Icons.point_of_sale_outlined, items: [
    MenuItem('/clients', Icons.people_outline, 'Clientes'),
    MenuItem('/clients/orders', Icons.shopping_cart_outlined, 'Órdenes de salida'),
    MenuItem('/clients/returns', Icons.keyboard_return, 'Devoluciones clientes'),
  ]),
  MenuEntry(title: 'CFDIs', icon: Icons.receipt_long_outlined, items: [
    MenuItem('/cfdis/facturas', Icons.description_outlined, 'Facturas'),
    MenuItem('/cfdis/complementos-pago', Icons.payments_outlined, 'Complementos de pago'),
    MenuItem('/cfdis/factura-global', Icons.point_of_sale_outlined, 'Factura global'),
    MenuItem('/cfdis/notas-credito', Icons.undo, 'Notas de crédito'),
    MenuItem('/cfdis/configuracion', Icons.badge_outlined, 'Configuración fiscal'),
  ]),
  MenuEntry.divider(),
  MenuEntry(title: 'Administración', icon: Icons.settings_outlined, items: [
    MenuItem('/users', Icons.group_outlined, 'Usuarios'),
    MenuItem('/permissions', Icons.admin_panel_settings_outlined, 'Permisos'),
    MenuItem('/warehouses', Icons.warehouse_outlined, 'Almacenes'),
    MenuItem('/account-settings', Icons.settings_outlined, 'Ajustes de cuenta'),
  ]),
  MenuEntry(title: 'Ayuda', icon: Icons.support_agent, items: [
    MenuItem('/help/tutorials', Icons.school_outlined, 'Tutoriales'),
    MenuItem('/help/boxy', Icons.smart_toy_outlined, 'Boxy'),
    MenuItem('/help/suggestions', Icons.lightbulb_outline, 'Sugerencias'),
  ]),
];

const _cfdiDocumentPaths = ['/cfdis/facturas', '/cfdis/complementos-pago', '/cfdis/factura-global', '/cfdis/notas-credito'];
const _inventorySuppliersItem = MenuItem('/suppliers', Icons.local_shipping_outlined, 'Proveedores');

List<MenuEntry> visibleModules(UserProfile? user) {
  final isAdmin = user?.isAdmin ?? false;
  final canViewSaleInvoices = user?.canReadSaleInvoices ?? false;
  final invoicing = user?.invoicingActive ?? false;

  final visible = allModules
      .where((m) => m.divider || m.title != 'Backoffice' || (user?.backofficePermission ?? false))
      .where((m) => m.divider || isAdmin || m.title != 'Administración')
      .map((m) => m.items == null
          ? m
          : m.copyWith(
              items: m.items!.where((item) {
                if (_cfdiDocumentPaths.contains(item.path)) return canViewSaleInvoices;
                if (item.path == '/cfdis/configuracion') return isAdmin;
                return true;
              }).toList()))
      // Sin Facturación, el catálogo de proveedores vive dentro de Inventario.
      .map((m) => m.title == 'Inventario' && m.items != null && !invoicing
          ? m.copyWith(items: [...m.items!, _inventorySuppliersItem])
          : m)
      .where((m) => m.divider || m.title != 'CFDIs' || !invoicing || (m.items?.isNotEmpty ?? false))
      .map((m) {
    if (m.divider) return m;
    final locked = m.title == 'Punto de venta'
        ? !(user?.posActive ?? false) || !(user?.canReadPos ?? false)
        : ['Compras', 'Ventas', 'CFDIs'].contains(m.title) && !invoicing;
    return locked ? m.copyWith(locked: true, path: integrationsPath, clearItems: true) : m;
  }).toList();

  // Un separador sin módulos después queda colgado.
  return [
    for (var i = 0; i < visible.length; i++)
      if (!visible[i].divider || visible.skip(i + 1).any((e) => !e.divider)) visible[i],
  ];
}
