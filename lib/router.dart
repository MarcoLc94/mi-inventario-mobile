import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import 'core/modules.dart';
import 'core/session.dart';
import 'features/adjustments/adjustment_detail_screen.dart';
import 'features/adjustments/adjustments_screen.dart';
import 'features/adjustments/new_adjustment_screen.dart';
import 'features/auth/lock_screen.dart';
import 'features/auth/login_screen.dart';
import 'features/auth/splash_screen.dart';
import 'features/billing/billing_screen.dart';
import 'features/categories/categories_screen.dart';
import 'features/cfdis/cfdi_catalogs.dart';
import 'features/cfdis/cfdi_document_detail_screen.dart';
import 'features/cfdis/cfdi_documents_screen.dart';
import 'features/cfdis/fiscal_settings_screen.dart';
import 'features/cfdis/global_invoice_new_screen.dart';
import 'features/cfdis/sale_invoice_detail_screen.dart';
import 'features/cfdis/sale_invoices_screen.dart';
import 'features/clients/client_detail_screen.dart';
import 'features/clients/clients_screen.dart';
import 'features/home/home_screen.dart';
import 'features/lots/lot_detail_screen.dart';
import 'features/lots/lots_screen.dart';
import 'features/manual_inventory/manual_inventory_screen.dart';
import 'features/manual_inventory/receipts_screen.dart';
import 'features/placeholder/module_placeholder.dart';
import 'features/pos/pos_screen.dart';
import 'features/pos/pos_sessions_screen.dart';
import 'features/pos/pos_tickets_screen.dart';
import 'features/products/product_detail_screen.dart';
import 'features/products/products_screen.dart';
import 'features/purchases/purchase_order_detail_screen.dart';
import 'features/purchases/purchase_order_form_screen.dart';
import 'features/purchases/purchase_orders_screen.dart';
import 'features/returns/new_return_screen.dart';
import 'features/returns/return_detail_screen.dart';
import 'features/returns/return_kind.dart';
import 'features/returns/returns_screen.dart';
import 'features/sale_orders/sale_order_detail_screen.dart';
import 'features/sale_orders/sale_order_form_screen.dart';
import 'features/sale_orders/sale_orders_screen.dart';
import 'features/settings/settings_screen.dart';
import 'features/stock_history/stock_history_screen.dart';
import 'features/suppliers/supplier_detail_screen.dart';
import 'features/suppliers/suppliers_screen.dart';
import 'features/transfers/new_transfer_screen.dart';
import 'features/transfers/transfer_detail_screen.dart';
import 'features/transfers/transfers_screen.dart';
import 'widgets/app_shell.dart';

/// Rutas con las mismas direcciones que la web, para que el menú y los
/// enlaces (p. ej. de una tarea del inicio) funcionen igual.
GoRouter buildRouter(SessionController session) {
  final implemented = <String, Widget Function(GoRouterState)>{
    '/': (_) => const HomeScreen(),
    '/products': (state) => ProductsScreen(initialFilter: state.uri.queryParameters['filter']),
    '/settings': (_) => const SettingsScreen(),
    '/billing': (_) => const BillingScreen(),
    '/categories': (_) => const CategoriesScreen(),
    '/inventory-adjustments': (_) => const AdjustmentsScreen(),
    '/transfers': (_) => const TransfersScreen(),
    '/inventory/lots': (_) => const LotsScreen(),
    '/stock-history': (_) => const StockHistoryScreen(),
    '/inventory/receipts': (_) => const ReceiptsScreen(),
    '/suppliers': (_) => const SuppliersScreen(),
    '/suppliers/orders': (_) => const PurchaseOrdersScreen(),
    '/suppliers/returns': (_) => const ReturnsScreen(kind: ReturnKind.supplier),
    '/clients': (_) => const ClientsScreen(),
    '/clients/orders': (_) => const SaleOrdersScreen(),
    '/clients/returns': (_) => const ReturnsScreen(kind: ReturnKind.client),
    '/pos': (_) => const PosScreen(),
    '/pos/tickets': (_) => const PosTicketsScreen(),
    '/pos/cortes': (_) => const PosSessionsScreen(),
    '/cfdis/facturas': (_) => const SaleInvoicesScreen(),
    '/cfdis/complementos-pago': (_) => const CfdiDocumentsScreen(kind: CfdiKind.payment),
    '/cfdis/notas-credito': (_) => const CfdiDocumentsScreen(kind: CfdiKind.creditNote),
    '/cfdis/factura-global': (_) => const CfdiDocumentsScreen(kind: CfdiKind.globalInvoice),
    '/cfdis/configuracion': (_) => const FiscalSettingsScreen(),
  };

  // Pantallas de detalle o formulario (se apilan sobre la lista, con botón atrás).
  final details = <String, Widget Function(GoRouterState)>{
    '/products/:id': (state) => ProductDetailScreen(id: state.pathParameters['id']!),
    '/inventory-adjustments/new': (_) => const NewAdjustmentScreen(),
    '/inventory-adjustments/:id': (state) => AdjustmentDetailScreen(id: state.pathParameters['id']!),
    '/transfers/new': (_) => const NewTransferScreen(),
    '/transfers/:id': (state) => TransferDetailScreen(id: state.pathParameters['id']!),
    '/inventory/lots/:id': (state) => LotDetailScreen(id: state.pathParameters['id']!),
    '/inventory/manual': (state) => ManualInventoryScreen(direction: state.uri.queryParameters['type'] == 'OUT' ? 'OUT' : 'IN'),
    '/suppliers/detail/:id': (state) => SupplierDetailScreen(id: state.pathParameters['id']!),
    '/suppliers/orders/create': (_) => const PurchaseOrderFormScreen(),
    '/suppliers/orders/:id': (state) => PurchaseOrderDetailScreen(id: state.pathParameters['id']!),
    '/suppliers/returns/new': (_) => const NewReturnScreen(kind: ReturnKind.supplier),
    '/suppliers/returns/:id': (state) => ReturnDetailScreen(kind: ReturnKind.supplier, id: state.pathParameters['id']!),
    '/clients/orders/create': (_) => const SaleOrderFormScreen(),
    '/clients/orders/:id': (state) => SaleOrderDetailScreen(id: state.pathParameters['id']!),
    '/clients/returns/new': (_) => const NewReturnScreen(kind: ReturnKind.client),
    '/clients/returns/:id': (state) => ReturnDetailScreen(kind: ReturnKind.client, id: state.pathParameters['id']!),
    '/clients/:id': (state) => ClientDetailScreen(id: state.pathParameters['id']!),
    '/cfdis/facturas/:id': (state) => SaleInvoiceDetailScreen(id: state.pathParameters['id']!),
    '/cfdis/complementos-pago/:id': (state) => CfdiDocumentDetailScreen(kind: CfdiKind.payment, id: state.pathParameters['id']!),
    '/cfdis/notas-credito/:id': (state) => CfdiDocumentDetailScreen(kind: CfdiKind.creditNote, id: state.pathParameters['id']!),
    '/cfdis/factura-global/nueva': (_) => const GlobalInvoiceNewScreen(),
    '/cfdis/factura-global/:id': (state) => CfdiDocumentDetailScreen(kind: CfdiKind.globalInvoice, id: state.pathParameters['id']!),
  };

  // Todo lo demás del menú: pantalla "llega pronto" con enlace a la web.
  final pending = <String, String>{
    for (final entry in allModules)
      if (entry.path != null && !implemented.containsKey(entry.path)) entry.path!: entry.title!,
    for (final entry in allModules)
      for (final item in entry.items ?? const <MenuItem>[])
        if (!implemented.containsKey(item.path)) item.path: item.label,
  };

  return GoRouter(
    refreshListenable: session,
    redirect: (context, state) {
      final location = state.matchedLocation;
      final target = switch (session.status) {
        SessionStatus.starting => '/splash',
        SessionStatus.signedOut => '/login',
        SessionStatus.locked => '/lock',
        SessionStatus.signedIn => null,
      };
      if (target != null) return location == target ? null : target;
      if (const ['/splash', '/login', '/lock'].contains(location)) return '/';
      return null;
    },
    routes: [
      GoRoute(path: '/splash', builder: (_, _) => const SplashScreen()),
      GoRoute(path: '/login', builder: (_, _) => const LoginScreen()),
      GoRoute(path: '/lock', builder: (_, _) => const LockScreen()),
      ShellRoute(
        builder: (_, _, child) => AppShell(child: child),
        routes: [
          for (final entry in implemented.entries)
            GoRoute(path: entry.key, pageBuilder: (_, state) => NoTransitionPage(child: entry.value(state))),
          for (final entry in details.entries) GoRoute(path: entry.key, builder: (_, state) => entry.value(state)),
          // Por ahora Ajustes de cuenta muestra el plan; empresa e integraciones llegan en la fase 6.
          GoRoute(path: '/account-settings', pageBuilder: (_, _) => const NoTransitionPage(child: BillingScreen(title: 'Ajustes de cuenta'))),
          for (final entry in pending.entries)
            if (entry.key != '/account-settings')
              GoRoute(
                path: entry.key,
                pageBuilder: (_, _) => NoTransitionPage(child: ModulePlaceholder(title: entry.value, path: entry.key)),
              ),
        ],
      ),
    ],
    errorBuilder: (_, state) => ModulePlaceholder(title: 'Mi Inventario', path: state.uri.toString()),
  );
}
