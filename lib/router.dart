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
import 'features/categories/categories_screen.dart';
import 'features/home/home_screen.dart';
import 'features/lots/lot_detail_screen.dart';
import 'features/lots/lots_screen.dart';
import 'features/manual_inventory/manual_inventory_screen.dart';
import 'features/manual_inventory/receipts_screen.dart';
import 'features/placeholder/module_placeholder.dart';
import 'features/products/product_detail_screen.dart';
import 'features/products/products_screen.dart';
import 'features/settings/settings_screen.dart';
import 'features/stock_history/stock_history_screen.dart';
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
    '/categories': (_) => const CategoriesScreen(),
    '/inventory-adjustments': (_) => const AdjustmentsScreen(),
    '/transfers': (_) => const TransfersScreen(),
    '/inventory/lots': (_) => const LotsScreen(),
    '/stock-history': (_) => const StockHistoryScreen(),
    '/inventory/receipts': (_) => const ReceiptsScreen(),
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
          GoRoute(
            path: '/account-settings',
            pageBuilder: (_, state) => NoTransitionPage(
                child: ModulePlaceholder(title: 'Ajustes de cuenta', path: '/account-settings?${state.uri.query}')),
          ),
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
