import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/api_client.dart';
import '../../core/catalogs.dart';
import '../../core/formatters.dart';
import '../../core/session.dart';
import '../../core/user_profile.dart';
import '../../widgets/async_states.dart';
import '../../widgets/form_fields.dart';
import '../../widgets/order_lines.dart';

/// Alta y edición de órdenes de compra (mismo payload que la web).
class PurchaseOrderFormScreen extends StatefulWidget {
  const PurchaseOrderFormScreen({super.key, this.order});

  /// Orden a editar (JSON de GET /purchase_orders/:id).
  final Map<String, dynamic>? order;

  @override
  State<PurchaseOrderFormScreen> createState() => _PurchaseOrderFormScreenState();
}

class _PurchaseOrderFormScreenState extends State<PurchaseOrderFormScreen> {
  late final Map<String, dynamic> _o = widget.order ?? const {};
  bool get _editing => widget.order != null;

  List<Map<String, dynamic>> _suppliers = [];
  List<Map<String, dynamic>> _warehouses = [];
  late int? _supplierId = (asMap(_o['supplier'])['id'] as num?)?.toInt();
  late String? _orderDate = _o['order_date']?.toString() ?? isoDate(DateTime.now());
  late String? _deliveryDate = _o['expected_delivery_date']?.toString() ?? isoDate(DateTime.now().add(const Duration(days: 7)));
  late final _deliveryPlace = TextEditingController(text: _o['delivery_place']?.toString() ?? '');
  late final _attention = TextEditingController(text: _o['attention']?.toString() ?? '');
  late final _email = TextEditingController(text: _o['email']?.toString() ?? '');
  late final _notes = TextEditingController(text: _o['notes']?.toString() ?? '');
  final _fxRate = TextEditingController(text: '17');
  late String _currency = _o['currency']?.toString() ?? 'MXN';
  late num _ivaRate = toNum(_o['iva_rate']) ?? 0.16;
  final _lines = <OrderLine>[];
  final _originalItemIds = <int>{};
  String? _folio;
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
    for (final c in [_deliveryPlace, _attention, _email, _notes, _fxRate]) {
      c.dispose();
    }
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
      final results = await Future.wait([api.get('/suppliers').then(asMapList), catalogs.activeWarehouses()]);
      _suppliers = results[0].where((s) => s['status'] == null || s['status'] == 'active' || s['id'] == _supplierId).toList();
      _warehouses = results[1];
      if (_editing && _lines.isEmpty) {
        for (final item in asMapList(_o['purchase_order_items'])) {
          final product = asMap(item['product']);
          final unit = await catalogs.unit(product['base_unit']?.toString());
          final presentation = item['presentation_ref']?.toString() ?? 'base';
          _originalItemIds.add((item['id'] as num).toInt());
          _lines.add(OrderLine(
            id: (item['id'] as num).toInt(),
            product: product,
            unit: unit,
            warehouseId: (item['warehouse_id'] as num?)?.toInt(),
            presentation: presentation,
            quantity: toNum(presentation == 'base' ? item['quantity'] : item['presentation_quantity'] ?? item['quantity']),
            price: toNum(presentation == 'base' ? item['unit_price'] : item['presentation_unit_price'] ?? item['unit_price']),
          ));
        }
      }
      if (_deliveryPlace.text.isEmpty && _warehouses.isNotEmpty) _deliveryPlace.text = _warehouses.first['name'].toString();
      if (_supplierId != null && !_editing) _loadFolio();
    } catch (error) {
      _loadError = error;
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _loadFolio() async {
    try {
      final data = asMap(await context.read<ApiClient>().get('/suppliers/$_supplierId/next_folio_preview'));
      if (mounted) setState(() => _folio = data['formatted_folio']?.toString());
    } catch (_) {
      if (mounted) setState(() => _folio = null);
    }
  }

  int? get _defaultWarehouseId {
    final match = _warehouses.where((w) => w['name'] == _deliveryPlace.text.trim()).firstOrNull ?? _warehouses.firstOrNull;
    return (match?['id'] as num?)?.toInt();
  }

  Future<void> _save() async {
    final fx = num.tryParse(_fxRate.text.trim()) ?? 0;
    String? message;
    if (_supplierId == null) {
      message = 'Selecciona un proveedor.';
    } else if (_orderDate == null || _deliveryDate == null) {
      message = 'Indica la fecha de la orden y la de entrega.';
    } else if (_deliveryDate!.compareTo(_orderDate!) < 0) {
      message = 'La entrega no puede ser antes de la fecha de la orden.';
    } else if (_currency == 'USD' && fx <= 0) {
      message = 'Escribe un tipo de cambio válido.';
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
    final amounts = orderAmounts(_lines, _ivaRate);
    final currentIds = _lines.map((l) => l.id).whereType<int>().toSet();
    final payload = {
      'purchase_order': {
        'supplier_id': _supplierId,
        'order_date': _orderDate,
        'expected_delivery_date': _deliveryDate,
        'delivery_place': _deliveryPlace.text.trim(),
        'attention': _attention.text.trim(),
        'email': _email.text.trim(),
        'notes': _notes.text.trim(),
        'buyer_id': context.read<SessionController>().profile?.id,
        'subtotal': amounts.subtotal,
        'iva': amounts.iva,
        'total': amounts.total,
        'iva_rate': _ivaRate,
        if (!_editing) 'currency': _currency,
        if (!_editing) 'fx_rate': _currency == 'USD' ? fx : 1.0,
        'purchase_order_items_attributes': [
          for (final line in _lines)
            {
              'id': ?line.id,
              'product_id': line.product['id'],
              'quantity': line.quantityValue,
              'unit_type': legacyUnitType(line.unit.code),
              'description': line.product['name'],
              'unit_price': line.priceValue,
              'warehouse_id': line.warehouseId,
              'presentation': line.presentation,
              'presentation_quantity': line.quantityValue,
              'presentation_unit_price': line.priceValue,
              if (line.id != null) '_destroy': false,
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
      _editing ? await api.put('/purchase_orders/${_o['id']}', payload) : await api.post('/purchase_orders', payload);
      if (!mounted) return;
      showMessage(context, _editing ? 'Orden actualizada' : 'Orden creada');
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
      appBar: AppBar(title: Text(_editing ? 'Editar compra ${_o['order_number'] ?? ''}' : 'Nueva orden de compra')),
      body: _loading
          ? const LoadingView()
          : _loadError != null
              ? ErrorView(error: _loadError!, onRetry: _load)
              : ListView(padding: const EdgeInsets.fromLTRB(16, 16, 16, 120), children: [
                  if (_error != null) Padding(padding: const EdgeInsets.only(bottom: 12), child: Text(_error!, style: TextStyle(color: theme.colorScheme.error))),
                  RecordDropdown(
                    label: 'Proveedor *',
                    records: _suppliers,
                    value: _supplierId,
                    icon: Icons.local_shipping_outlined,
                    onChanged: (v) {
                      setState(() {
                        _supplierId = v;
                        final supplier = _suppliers.where((s) => s['id'] == v).firstOrNull;
                        if (_email.text.isEmpty && supplier?['email'] != null) _email.text = supplier!['email'].toString();
                      });
                      if (!_editing) _loadFolio();
                    },
                  ),
                  if (_folio != null) Padding(padding: const EdgeInsets.only(top: 4), child: Text('Folio: $_folio', style: theme.textTheme.bodySmall)),
                  const SizedBox(height: 12),
                  Row(children: [
                    Expanded(child: DateField(label: 'Fecha', value: _orderDate, onChanged: (v) => setState(() => _orderDate = v))),
                    const SizedBox(width: 8),
                    Expanded(child: DateField(label: 'Entrega', value: _deliveryDate, onChanged: (v) => setState(() => _deliveryDate = v))),
                  ]),
                  const SizedBox(height: 12),
                  DropdownButtonFormField<String>(
                    initialValue: _warehouses.any((w) => w['name'] == _deliveryPlace.text) ? _deliveryPlace.text : null,
                    isExpanded: true,
                    decoration: const InputDecoration(labelText: 'Lugar de entrega', prefixIcon: Icon(Icons.warehouse_outlined)),
                    items: [for (final w in _warehouses) DropdownMenuItem(value: w['name'].toString(), child: Text(w['name'].toString()))],
                    onChanged: (v) => setState(() => _deliveryPlace.text = v ?? ''),
                  ),
                  const SizedBox(height: 12),
                  TextField(controller: _attention, decoration: const InputDecoration(labelText: 'Atención a')),
                  const SizedBox(height: 12),
                  TextField(controller: _email, keyboardType: TextInputType.emailAddress, decoration: const InputDecoration(labelText: 'Correo del proveedor')),
                  if (!_editing) ...[
                    const SizedBox(height: 12),
                    Row(children: [
                      Expanded(
                        child: DropdownButtonFormField<String>(
                          initialValue: _currency,
                          decoration: const InputDecoration(labelText: 'Moneda'),
                          items: const [DropdownMenuItem(value: 'MXN', child: Text('MXN')), DropdownMenuItem(value: 'USD', child: Text('USD'))],
                          onChanged: (v) => setState(() => _currency = v ?? 'MXN'),
                        ),
                      ),
                      if (_currency == 'USD') ...[
                        const SizedBox(width: 8),
                        Expanded(
                          child: TextField(
                            controller: _fxRate,
                            keyboardType: const TextInputType.numberWithOptions(decimal: true),
                            decoration: const InputDecoration(labelText: 'Tipo de cambio'),
                          ),
                        ),
                      ],
                    ]),
                    if (_currency == 'USD')
                      Padding(padding: const EdgeInsets.only(top: 4), child: Text('Captura los precios en dólares.', style: theme.textTheme.bodySmall)),
                  ],
                  const SizedBox(height: 12),
                  TextField(controller: _notes, maxLines: 2, decoration: const InputDecoration(labelText: 'Observaciones')),
                  const SizedBox(height: 20),
                  Text('Productos', style: theme.textTheme.titleMedium),
                  const SizedBox(height: 8),
                  OrderLinesEditor(
                    lines: _lines,
                    warehouses: _warehouses,
                    priceKey: 'purchase_price',
                    defaultWarehouseId: _defaultWarehouseId,
                    onChanged: () => setState(() {}),
                  ),
                  const SizedBox(height: 12),
                  AmountsCard(lines: _lines, ivaRate: _ivaRate, currency: _currency, onIvaChanged: (v) => setState(() => _ivaRate = v)),
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
