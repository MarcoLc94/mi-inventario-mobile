import 'dart:async';

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../../core/api_client.dart';
import '../../core/formatters.dart';
import '../../core/user_profile.dart';
import '../../widgets/app_shell.dart';
import '../../widgets/async_states.dart';
import '../../widgets/form_fields.dart';

const _referenceRoutes = {
  'SaleOrder': '/clients/orders',
  'PurchaseOrder': '/suppliers/orders',
  'PurchaseOrderItem': '/suppliers/orders',
  'AdjustmentItem': '/inventory-adjustments',
  'InventoryAdjustment': '/inventory-adjustments',
  'InventoryTransferItem': '/transfers',
  'Transfer': '/transfers',
  'ReturnItem': '/clients/returns',
  'ClientReturn': '/clients/returns',
  'SupplierReturnItem': '/suppliers/returns',
  'SupplierReturn': '/suppliers/returns',
};
const _referenceLabels = {
  'SaleOrder': 'Orden de venta',
  'PurchaseOrder': 'Orden de compra',
  'PurchaseOrderItem': 'Orden de compra',
  'InventoryAdjustment': 'Ajuste de inventario',
  'AdjustmentItem': 'Ajuste de inventario',
  'InventoryTransferItem': 'Transferencia',
  'Transfer': 'Transferencia',
  'Product': 'Registro inicial',
  'ManualInventoryMovement': 'Movimiento manual',
  'Movement': 'Movimiento',
  'InternalConsumption': 'Consumo interno',
  'ClientReturn': 'Devolución de cliente',
  'ReturnItem': 'Devolución de cliente',
  'SupplierReturn': 'Devolución a proveedor',
  'SupplierReturnItem': 'Devolución a proveedor',
};
const _originFilters = {
  null: 'Todos los orígenes',
  'SaleOrder': 'Orden de venta',
  'PurchaseOrder': 'Orden de compra',
  'adjustment': 'Ajuste de inventario',
  'ManualInventoryMovement': 'Entradas y salidas manuales',
  'Product': 'Registro inicial',
  'none': 'Sin referencia',
};

/// Historial de movimientos de existencias (GET /stock_movements), con filtros
/// por producto, fechas y origen, y totales de entradas y salidas.
class StockHistoryScreen extends StatefulWidget {
  const StockHistoryScreen({super.key});

  @override
  State<StockHistoryScreen> createState() => _StockHistoryScreenState();
}

class _StockHistoryScreenState extends State<StockHistoryScreen> {
  final _scroll = ScrollController();
  final _search = TextEditingController();
  Timer? _debounce;
  String? _from;
  String? _to;
  String? _origin;
  final _items = <Map<String, dynamic>>[];
  Map<String, dynamic> _summary = {};
  int _page = 0;
  int _totalPages = 1;
  int _total = 0;
  bool _loading = false;
  Object? _error;
  int _generation = 0;

  @override
  void initState() {
    super.initState();
    _scroll.addListener(() {
      if (_scroll.position.pixels > _scroll.position.maxScrollExtent - 400) _loadMore();
    });
    _reload();
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _scroll.dispose();
    _search.dispose();
    super.dispose();
  }

  Future<void> _reload() async {
    _generation++;
    setState(() {
      _items.clear();
      _page = 0;
      _totalPages = 1;
      _error = null;
    });
    await _loadMore();
  }

  Future<void> _loadMore() async {
    if (_loading || _page >= _totalPages) return;
    final generation = _generation;
    setState(() => _loading = true);
    try {
      final data = asMap(await context.read<ApiClient>().get('/stock_movements', query: {
        'page': _page + 1,
        'per_page': 30,
        'search': _search.text.trim(),
        'start_date': _from,
        'end_date': _to,
        'reference_type': _origin,
      }));
      if (!mounted || generation != _generation) return;
      final meta = asMap(data['meta']);
      setState(() {
        _items.addAll(asMapList(data['data']));
        _page++;
        _totalPages = (meta['total_pages'] as num?)?.toInt() ?? 1;
        _total = (meta['total'] as num?)?.toInt() ?? 0;
        _summary = asMap(meta['summary']);
      });
    } catch (error) {
      if (mounted && generation == _generation) setState(() => _error = error);
    } finally {
      if (mounted && generation == _generation) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final invalidDates = _from != null && _to != null && _from!.compareTo(_to!) > 0;
    return ModuleScaffold(
      title: 'Movimientos',
      body: RefreshIndicator(
        onRefresh: _reload,
        child: ListView.builder(
          controller: _scroll,
          physics: const AlwaysScrollableScrollPhysics(),
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
          itemCount: _items.length + 2,
          itemBuilder: (context, index) {
            if (index == 0) {
              return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                TextField(
                  controller: _search,
                  onChanged: (_) {
                    _debounce?.cancel();
                    _debounce = Timer(const Duration(milliseconds: 400), _reload);
                  },
                  decoration: const InputDecoration(hintText: 'Buscar por nombre', prefixIcon: Icon(Icons.search)),
                ),
                const SizedBox(height: 8),
                Row(children: [
                  Expanded(child: DateField(label: 'Desde', value: _from, clearable: true, onChanged: (v) {
                    setState(() => _from = v);
                    _reload();
                  })),
                  const SizedBox(width: 8),
                  Expanded(child: DateField(label: 'Hasta', value: _to, clearable: true, onChanged: (v) {
                    setState(() => _to = v);
                    _reload();
                  })),
                ]),
                if (invalidDates)
                  Padding(
                    padding: const EdgeInsets.only(top: 4),
                    child: Text('La fecha de inicio debe ser anterior o igual a la fecha final.', style: TextStyle(color: theme.colorScheme.error)),
                  ),
                const SizedBox(height: 8),
                DropdownButtonFormField<String?>(
                  initialValue: _origin,
                  decoration: const InputDecoration(labelText: 'Origen del movimiento'),
                  items: [for (final e in _originFilters.entries) DropdownMenuItem(value: e.key, child: Text(e.value))],
                  onChanged: (v) {
                    setState(() => _origin = v);
                    _reload();
                  },
                ),
                const SizedBox(height: 12),
                Row(children: [
                  _SummaryTile('Entradas', formatNumber(_summary['total_in'] ?? 0), Colors.green.shade700),
                  const SizedBox(width: 8),
                  _SummaryTile('Salidas', formatNumber(_summary['total_out'] ?? 0), theme.colorScheme.error),
                  const SizedBox(width: 8),
                  _SummaryTile('Balance', formatNumber(_summary['balance'] ?? 0), theme.colorScheme.primary),
                ]),
                const SizedBox(height: 8),
                Text('${formatNumber(_total)} movimientos', style: theme.textTheme.bodySmall),
                const SizedBox(height: 8),
                if (_items.isEmpty && _error != null) ErrorView(error: _error!, onRetry: _reload),
                if (_items.isEmpty && !_loading && _error == null) const Padding(padding: EdgeInsets.all(32), child: Center(child: Text('Sin movimientos con estos filtros'))),
              ]);
            }
            if (index == _items.length + 1) {
              return _page < _totalPages && _error == null
                  ? const Padding(padding: EdgeInsets.all(16), child: Center(child: CircularProgressIndicator()))
                  : const SizedBox.shrink();
            }
            final m = _items[index - 1];
            final entry = m['movement_type'] == 'IN';
            final color = entry ? Colors.green.shade700 : theme.colorScheme.error;
            final reference = m['reference_type']?.toString();
            final route = _referenceRoutes[reference];
            final refId = m['reference_document_id'] ?? m['reference_id'];
            return Card(
              margin: const EdgeInsets.only(bottom: 8),
              child: ListTile(
                leading: Icon(entry ? Icons.south_west : Icons.north_east, color: color),
                title: Text(asMap(m['product'])['name']?.toString() ?? 'Producto'),
                subtitle: Text([
                  formatDateTime(m['created_at']),
                  _referenceLabels[reference] ?? 'Sin referencia',
                  if (asMap(m['warehouse'])['name'] != null) asMap(m['warehouse'])['name'],
                ].join(' · ')),
                trailing: Column(mainAxisAlignment: MainAxisAlignment.center, crossAxisAlignment: CrossAxisAlignment.end, children: [
                  Text('${entry ? '+' : '-'}${formatNumber(m['quantity'])}', style: theme.textTheme.titleSmall?.copyWith(color: color)),
                  Text('Queda ${formatNumber(m['new_stock'])}', style: theme.textTheme.labelSmall),
                ]),
                onTap: route == null || refId == null ? null : () => context.push('$route/$refId'),
              ),
            );
          },
        ),
      ),
    );
  }
}

class _SummaryTile extends StatelessWidget {
  const _SummaryTile(this.label, this.value, this.color);
  final String label;
  final String value;
  final Color color;

  @override
  Widget build(BuildContext context) => Expanded(
        child: Card(
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(label, style: Theme.of(context).textTheme.labelSmall),
              FittedBox(child: Text(value, style: Theme.of(context).textTheme.titleMedium?.copyWith(color: color))),
            ]),
          ),
        ),
      );
}
