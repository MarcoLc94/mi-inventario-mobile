import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../../core/api_client.dart';
import '../../core/formatters.dart';
import '../../core/session.dart';
import '../../core/user_profile.dart';
import '../../widgets/app_shell.dart';
import '../../widgets/async_states.dart';
import 'dashboard_data.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  bool _loading = true;
  List<Map<String, dynamic>>? _products;
  List<Map<String, dynamic>>? _purchases;
  List<Map<String, dynamic>>? _sales;
  Map<String, dynamic>? _pos;
  List<String> _errors = [];
  Object? _blocking;
  DateTime? _updatedAt;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<List<Map<String, dynamic>>> _allPages(String path, [String? status]) async {
    final api = context.read<ApiClient>();
    final items = <Map<String, dynamic>>[];
    var totalPages = 1;
    for (var page = 1; page <= totalPages; page++) {
      final result = PageResult.fromJson(await api.get(path,
          query: {'page': page, 'per_page': 250, 'sort_by': 'id', 'sort_dir': 'asc', 'status': status}));
      items.addAll(result.items);
      totalPages = result.totalPages;
    }
    return items;
  }

  Future<void> _load() async {
    final user = context.read<SessionController>().profile;
    final api = context.read<ApiClient>();
    final showInventory = user?.enabledModules.contains('inventory') ?? false;
    final showInvoicing = user?.invoicingActive ?? false;
    final showPos = (user?.enabledModules.contains('pos') ?? false) && (user?.canReadPos ?? false);
    setState(() {
      _loading = true;
      _blocking = null;
    });

    Future<T?> capture<T>(bool enabled, String label, Future<T> Function() run, List<String> errors) async {
      if (!enabled) return null;
      try {
        return await run();
      } on ApiException catch (error) {
        if (error.subscriptionInactive) _blocking = error;
        errors.add(label);
        return null;
      } catch (_) {
        errors.add(label);
        return null;
      }
    }

    final errors = <String>[];
    final results = await Future.wait([
      capture(showInventory, 'productos', () => _allPages('/products'), errors),
      capture(showInvoicing, 'compras', () async => [
            ...await _allPages('/purchase_orders', 'approved'),
            ...await _allPages('/purchase_orders', 'partially_received'),
          ], errors),
      capture(showInvoicing, 'ventas', () => _allPages('/sale_orders', 'approved'), errors),
      capture(showPos, 'punto de venta', () async => asMap(asMap(await api.get('/dashboard_summary'))['pos']), errors),
    ]);
    if (!mounted) return;
    setState(() {
      _products = results[0] as List<Map<String, dynamic>>?;
      _purchases = results[1] as List<Map<String, dynamic>>?;
      _sales = results[2] as List<Map<String, dynamic>>?;
      _pos = results[3] as Map<String, dynamic>?;
      _errors = errors;
      _updatedAt = DateTime.now();
      _loading = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    final user = context.watch<SessionController>().profile;
    final showInventory = user?.enabledModules.contains('inventory') ?? false;
    final showInvoicing = user?.invoicingActive ?? false;
    final showPos = (user?.enabledModules.contains('pos') ?? false) && (user?.canReadPos ?? false);
    final theme = Theme.of(context);

    Widget body;
    if (_loading && _updatedAt == null) {
      body = const LoadingView(label: 'Cargando tus módulos…');
    } else if (_blocking != null) {
      body = ErrorView(error: _blocking!, onRetry: _load);
    } else {
      final stats = _products == null ? null : InventorySummary(_products!);
      final tasks = buildTasks(_purchases ?? const [], _sales ?? const []);
      final attention = (_products ?? const <Map<String, dynamic>>[])
          .where((p) => const [StockState.out, StockState.low].contains(stockState(p)))
          .toList()
        ..sort((a, b) => (toNum(a['stock']) ?? 0).compareTo(toNum(b['stock']) ?? 0));
      body = RefreshIndicator(
        onRefresh: _load,
        child: ListView(padding: const EdgeInsets.all(16), children: [
          Text('TU OPERACIÓN, DE UN VISTAZO',
              style: theme.textTheme.labelSmall?.copyWith(color: theme.colorScheme.primary, letterSpacing: 1.2)),
          const SizedBox(height: 4),
          Text('Hola${user?.firstName.isNotEmpty == true ? ', ${user!.firstName}' : ''}',
              style: theme.textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w700)),
          Text('Revisa lo que necesita atención y continúa con tu día.', style: theme.textTheme.bodyMedium),
          if (_updatedAt != null)
            Padding(
              padding: const EdgeInsets.only(top: 4),
              child: Text('Última consulta: ${formatDateTime(_updatedAt!.toIso8601String())}',
                  style: theme.textTheme.bodySmall),
            ),
          if (_errors.isNotEmpty) ...[
            const SizedBox(height: 12),
            Card(
              color: theme.colorScheme.errorContainer,
              child: ListTile(
                leading: const Icon(Icons.warning_amber_rounded),
                title: Text('No se pudo cargar: ${_errors.join(', ')}.'),
                subtitle: const Text('Desliza hacia abajo para reintentar.'),
              ),
            ),
          ],
          const SizedBox(height: 16),
          if (!showInventory && !showInvoicing && !showPos)
            const Card(
              child: Padding(
                padding: EdgeInsets.all(20),
                child: Text('Tu espacio está listo. Activa los módulos de tu empresa en Ajustes de cuenta → Integraciones.'),
              ),
            ),
          if (showPos) ...[
            _SectionTitle('Punto de venta', action: 'Ir a caja', onTap: () => context.go('/pos')),
            _KpiGrid(children: [
              _Kpi('Ventas de hoy', formatNumber(_pos?['sales_today']), Icons.receipt_outlined,
                  onTap: () => context.go('/pos/tickets')),
              _Kpi('Total cobrado hoy', formatMoney(_pos?['total_today']), Icons.payments_outlined,
                  onTap: () => context.go('/pos/tickets')),
              _Kpi(user?.isAdmin == true ? 'Cajas abiertas' : 'Mis cajas abiertas', formatNumber(_pos?['open_sessions']),
                  Icons.point_of_sale_outlined,
                  onTap: () => context.go('/pos/cortes')),
            ]),
            const SizedBox(height: 16),
          ],
          if (showInventory || showInvoicing)
            _KpiGrid(children: [
              if (showInventory) ...[
                _Kpi('Productos registrados', stats == null ? '—' : formatNumber(stats.total), Icons.inventory_2_outlined,
                    onTap: () => context.go('/products')),
                _Kpi('Necesitan reposición', stats == null ? '—' : formatNumber(stats.attention), Icons.warning_amber_rounded,
                    note: stats == null ? null : '${stats.out} sin existencias · ${stats.low} con stock bajo',
                    warning: true,
                    onTap: () => context.go('/products?filter=attention')),
              ],
              if (showInvoicing) ...[
                _Kpi('Compras por recibir', _purchases == null ? '—' : formatNumber(_purchases!.length),
                    Icons.move_to_inbox_outlined,
                    onTap: () => context.go('/suppliers/orders')),
                _Kpi('Ventas por entregar', _sales == null ? '—' : formatNumber(_sales!.length), Icons.outbox_outlined,
                    onTap: () => context.go('/clients/orders')),
              ],
            ]),
          if (showInvoicing && tasks.isNotEmpty) ...[
            const SizedBox(height: 20),
            const _SectionTitle('Pendientes por fecha'),
            Card(
              child: Column(children: [
                for (final task in tasks.take(8))
                  ListTile(
                    leading: Icon(task.kind == TaskKind.purchase ? Icons.move_to_inbox_outlined : Icons.outbox_outlined),
                    title: Text(task.title),
                    subtitle: Text('${task.subtitle} · ${task.status}'),
                    trailing: Text(dueLabel(task.days),
                        style: TextStyle(
                            color: (task.days ?? 1) < 0 ? theme.colorScheme.error : null, fontWeight: FontWeight.w600)),
                    onTap: () => context.go(task.path),
                  ),
              ]),
            ),
          ],
          if (showInventory && attention.isNotEmpty) ...[
            const SizedBox(height: 20),
            _SectionTitle('Por reponer', action: 'Ver todos', onTap: () => context.go('/products?filter=attention')),
            Card(
              child: Column(children: [
                for (final product in attention.take(8))
                  ListTile(
                    title: Text(product['name']?.toString() ?? ''),
                    subtitle: Text(stockLabels[stockState(product)]!),
                    trailing: Text(formatNumber(product['stock']),
                        style: theme.textTheme.titleMedium?.copyWith(
                            color: stockState(product) == StockState.out ? theme.colorScheme.error : null)),
                    onTap: () => context.push('/products/${product['id']}'),
                  ),
              ]),
            ),
          ],
          const SizedBox(height: 24),
        ]),
      );
    }

    return ModuleScaffold(
      title: 'Inicio',
      actions: [
        IconButton(tooltip: 'Actualizar', onPressed: _loading ? null : _load, icon: const Icon(Icons.refresh)),
      ],
      body: body,
    );
  }
}

class _SectionTitle extends StatelessWidget {
  const _SectionTitle(this.title, {this.action, this.onTap});
  final String title;
  final String? action;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(bottom: 8),
        child: Row(children: [
          Expanded(child: Text(title, style: Theme.of(context).textTheme.titleMedium)),
          if (action != null) TextButton(onPressed: onTap, child: Text(action!)),
        ]),
      );
}

class _KpiGrid extends StatelessWidget {
  const _KpiGrid({required this.children});
  final List<Widget> children;

  /// Dos por fila y del alto de su contenido (con letra grande, una
  /// proporción fija dejaba tarjetas enormes o cortadas).
  @override
  Widget build(BuildContext context) => Column(children: [
        for (var i = 0; i < children.length; i += 2)
          Padding(
            padding: EdgeInsets.only(bottom: i + 2 < children.length ? 12 : 0),
            child: IntrinsicHeight(
              child: Row(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                Expanded(child: children[i]),
                const SizedBox(width: 12),
                Expanded(child: i + 1 < children.length ? children[i + 1] : const SizedBox.shrink()),
              ]),
            ),
          ),
      ]);
}

class _Kpi extends StatelessWidget {
  const _Kpi(this.label, this.value, this.icon, {this.note, this.warning = false, this.onTap});
  final String label;
  final String value;
  final IconData icon;
  final String? note;
  final bool warning;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final color = warning ? theme.colorScheme.error : theme.colorScheme.primary;
    return Card(
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [
              Expanded(child: Text(label, style: theme.textTheme.bodySmall, maxLines: 2)),
              Icon(icon, size: 20, color: color),
            ]),
            const SizedBox(height: 10),
            const Spacer(),
            FittedBox(
              fit: BoxFit.scaleDown,
              alignment: Alignment.centerLeft,
              child: Text(value, style: theme.textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w700)),
            ),
            if (note != null) Text(note!, style: theme.textTheme.labelSmall, maxLines: 2, overflow: TextOverflow.ellipsis),
          ]),
        ),
      ),
    );
  }
}
