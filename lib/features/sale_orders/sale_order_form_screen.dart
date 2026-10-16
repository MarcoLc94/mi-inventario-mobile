import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/api_client.dart';
import '../../core/catalogs.dart';
import '../../core/formatters.dart';
import '../../core/user_profile.dart';
import '../../widgets/async_states.dart';
import '../../widgets/form_fields.dart';
import '../../widgets/order_lines.dart';

/// Alta y edición de órdenes de venta (mismo payload que la web).
class SaleOrderFormScreen extends StatefulWidget {
  const SaleOrderFormScreen({super.key, this.order});
  final Map<String, dynamic>? order;

  @override
  State<SaleOrderFormScreen> createState() => _SaleOrderFormScreenState();
}

class _SaleOrderFormScreenState extends State<SaleOrderFormScreen> {
  late final Map<String, dynamic> _o = widget.order ?? const {};
  bool get _editing => widget.order != null;

  List<Map<String, dynamic>> _clients = [];
  List<Map<String, dynamic>> _warehouses = [];
  late int? _clientId = (asMap(_o['client'])['id'] as num?)?.toInt();
  late String? _orderDate = _o['order_date']?.toString() ?? isoDate(DateTime.now());
  late String? _deliveryDate = _o['expected_delivery_date']?.toString() ?? isoDate(DateTime.now());
  late final _notes = TextEditingController(text: _o['notes']?.toString() ?? '');
  late num _ivaRate = toNum(_o['iva_rate']) ?? 0.16;
  final _lines = <OrderLine>[];
  final _originalItemIds = <int>{};
  String? _nextNumber;
  bool _loading = true;
  Object? _loadError;
  bool _saving = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _notes.dispose();
    for (final line in _lines) {
      line.dispose();
    }
    super.dispose();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _loadError = null;
    });
    final api = context.read<ApiClient>();
    final catalogs = context.read<Catalogs>();
    try {
      final results = await Future.wait([
        api.get('/clients', query: {'per_page': 1000, 'sort_by': 'name', 'sort_dir': 'asc'}).then((d) => PageResult.fromJson(d).items),
        catalogs.activeWarehouses(),
      ]);
      _clients = results[0];
      _warehouses = results[1];
      if (_editing && _lines.isEmpty) {
        for (final item in asMapList(_o['sale_order_items'])) {
          if (item['product_id'] == null) continue;
          final product = asMap(item['product']);
          final presentation = item['presentation_ref']?.toString() ?? 'base';
          _originalItemIds.add((item['id'] as num).toInt());
          _lines.add(OrderLine(
            id: (item['id'] as num).toInt(),
            product: product,
            unit: await catalogs.unit(product['base_unit']?.toString()),
            warehouseId: (item['warehouse_id'] as num?)?.toInt(),
            presentation: presentation,
            quantity: toNum(presentation == 'base' ? item['quantity'] : item['presentation_quantity'] ?? item['quantity']),
            price: toNum(presentation == 'base' ? item['unit_price'] : item['presentation_unit_price'] ?? item['unit_price']),
          ));
        }
      }
    } catch (error) {
      _loadError = error;
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _loadNextNumber() async {
    if (_clientId == null || _editing) return;
    try {
      final data = asMap(await context.read<ApiClient>().get('/sale_orders/next_number', query: {'client_id': _clientId}));
      if (mounted) setState(() => _nextNumber = data['next_order_number']?.toString());
    } catch (_) {}
  }

  int? get _defaultWarehouseId => (_warehouses.firstOrNull?['id'] as num?)?.toInt();

  Future<void> _save() async {
    String? message;
    if (_clientId == null) {
      message = 'Selecciona un cliente.';
    } else if (_orderDate == null || _deliveryDate == null) {
      message = 'Indica la fecha de la orden y la de entrega.';
    } else if (_deliveryDate!.compareTo(_orderDate!) < 0) {
      message = 'La entrega no puede ser antes de la fecha de la orden.';
    } else {
      for (final line in _lines) {
        line.warehouseId ??= _defaultWarehouseId;
      }
      message = orderLinesError(_lines);
    }
    if (message != null) {
      setState(() => _error = message);
      return;
    }
    final currentIds = _lines.map((l) => l.id).whereType<int>().toSet();
    final payload = {
      'sale_order': {
        'client_id': _clientId,
        'order_date': _orderDate,
        'expected_delivery_date': _deliveryDate,
        'iva_rate': _ivaRate,
        if (!_editing) 'status': 'draft',
        'notes': _notes.text.trim(),
        'sale_order_items_attributes': [
          for (final line in _lines)
            {
              'id': ?line.id,
              'product_id': line.product['id'],
              'quantity': line.quantityValue,
              'unit_price': line.priceValue,
              'description': line.product['name'],
              'unit_type': legacyUnitType(line.unit.code),
              'warehouse_id': line.warehouseId,
              'presentation': line.presentation,
              'presentation_quantity': line.quantityValue,
              'presentation_unit_price': line.priceValue,
            },
          for (final id in _originalItemIds.difference(currentIds)) {'id': id, '_destroy': true},
        ],
      },
    };
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      final api = context.read<ApiClient>();
      _editing ? await api.put('/sale_orders/${_o['id']}', payload) : await api.post('/clients/$_clientId/sale_orders', payload);
      if (!mounted) return;
      showMessage(context, _editing ? 'Orden actualizada' : 'Orden de venta creada');
      Navigator.pop(context, true);
    } catch (error) {
      if (mounted) setState(() => _error = error.toString());
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(title: Text(_editing ? 'Editar venta ${_o['order_number'] ?? ''}' : 'Nueva orden de venta')),
      body: _loading
          ? const LoadingView()
          : _loadError != null
              ? ErrorView(error: _loadError!, onRetry: _load)
              : ListView(padding: const EdgeInsets.fromLTRB(16, 16, 16, 120), children: [
                  if (_error != null) Padding(padding: const EdgeInsets.only(bottom: 12), child: Text(_error!, style: TextStyle(color: theme.colorScheme.error))),
                  RecordDropdown(
                    label: 'Cliente *',
                    records: _clients,
                    value: _clientId,
                    icon: Icons.person_outline,
                    onChanged: (v) {
                      setState(() => _clientId = v);
                      _loadNextNumber();
                    },
                  ),
                  if (_nextNumber != null) Padding(padding: const EdgeInsets.only(top: 4), child: Text('Folio: $_nextNumber', style: theme.textTheme.bodySmall)),
                  const SizedBox(height: 12),
                  Row(children: [
                    Expanded(child: DateField(label: 'Fecha', value: _orderDate, onChanged: (v) => setState(() => _orderDate = v))),
                    const SizedBox(width: 8),
                    Expanded(child: DateField(label: 'Entrega', value: _deliveryDate, onChanged: (v) => setState(() => _deliveryDate = v))),
                  ]),
                  const SizedBox(height: 12),
                  TextField(controller: _notes, maxLines: 2, decoration: const InputDecoration(labelText: 'Observaciones')),
                  const SizedBox(height: 20),
                  Text('Productos', style: theme.textTheme.titleMedium),
                  const SizedBox(height: 8),
                  OrderLinesEditor(
                    lines: _lines,
                    warehouses: _warehouses,
                    priceKey: 'sale_price',
                    defaultWarehouseId: _defaultWarehouseId,
                    onChanged: () => setState(() {}),
                  ),
                  const SizedBox(height: 12),
                  AmountsCard(lines: _lines, ivaRate: _ivaRate, onIvaChanged: (v) => setState(() => _ivaRate = v)),
                ]),
      bottomNavigationBar: _loading || _loadError != null
          ? null
          : SafeArea(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: FilledButton(onPressed: _saving ? null : _save, child: Text(_saving ? 'Guardando…' : 'Guardar orden')),
              ),
            ),
    );
  }
}
