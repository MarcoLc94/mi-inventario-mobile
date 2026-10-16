import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/api_client.dart';
import '../../core/catalogs.dart';
import '../../core/formatters.dart';
import '../../core/ids.dart';
import '../../core/user_profile.dart';
import '../../widgets/form_fields.dart';

/// Registra un lote para piezas que ya están en el almacén sin lote asignado
/// (modo "assign" de POST /inventory_lots, igual que la web).
Future<Map<String, dynamic>?> showRegisterLotSheet(BuildContext context) => showModalBottomSheet<Map<String, dynamic>>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (_) => const _RegisterLotSheet(),
    );

class _RegisterLotSheet extends StatefulWidget {
  const _RegisterLotSheet();

  @override
  State<_RegisterLotSheet> createState() => _RegisterLotSheetState();
}

class _RegisterLotSheetState extends State<_RegisterLotSheet> {
  final _requestKey = newRequestKey();
  final _lot = TextEditingController();
  final _quantity = TextEditingController();
  final _query = TextEditingController();
  Timer? _debounce;
  List<Map<String, dynamic>> _warehouses = [];
  int? _warehouseId;
  List<Map<String, dynamic>> _results = [];
  Map<String, dynamic>? _product;
  Unit _unit = Unit.piece;
  String? _expiration;
  bool _searching = false;
  bool _saving = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    context.read<Catalogs>().activeWarehouses().then((w) {
      if (!mounted) return;
      setState(() {
        _warehouses = w;
        if (w.length == 1) _warehouseId = (w.first['id'] as num).toInt();
      });
      _search();
    });
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _lot.dispose();
    _quantity.dispose();
    _query.dispose();
    super.dispose();
  }

  Future<void> _search() async {
    if (_warehouseId == null) return;
    setState(() => _searching = true);
    try {
      final page = PageResult.fromJson(await context.read<ApiClient>().get('/products', query: {
        'per_page': 50,
        'in_warehouse_id': _warehouseId,
        'without_lot': true,
        'name': _query.text.trim(),
      }));
      if (mounted) setState(() => _results = page.items.where((p) => (toNum(p['unassigned_stock']) ?? 0) > 0).toList());
    } catch (_) {
      if (mounted) setState(() => _results = []);
    } finally {
      if (mounted) setState(() => _searching = false);
    }
  }

  Future<void> _choose(Map<String, dynamic> product) async {
    final unit = await context.read<Catalogs>().unit(product['base_unit']?.toString());
    if (mounted) {
      setState(() {
        _product = product;
        _unit = unit;
      });
    }
  }

  Future<void> _save() async {
    final available = toNum(_product?['unassigned_stock']) ?? 0;
    final quantity = num.tryParse(_quantity.text.trim());
    String? message;
    if (_lot.text.trim().isEmpty) {
      message = 'Escribe el número de lote.';
    } else if (quantity == null || !_unit.accepts(quantity)) {
      message = quantity == null || quantity <= 0 ? 'La cantidad debe ser mayor que cero.' : _unit.precisionMessage;
    } else if (quantity > available) {
      message = 'Solo hay ${formatNumber(available)} piezas sin lote en este almacén.';
    }
    if (message != null) {
      setState(() => _error = message);
      return;
    }
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      final created = await context.read<ApiClient>().post('/inventory_lots', {
        'mode': 'assign',
        'product_id': _product!['id'],
        'warehouse_id': _warehouseId,
        'lot_number': _lot.text.trim().toUpperCase(),
        'expiration_date': ?_expiration,
        'quantity': quantity,
        'request_key': _requestKey,
      });
      if (mounted) Navigator.pop(context, asMap(created));
    } catch (error) {
      if (mounted) setState(() => _error = error.toString());
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final product = _product;
    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
      child: SizedBox(
        height: MediaQuery.of(context).size.height * .85,
        child: ListView(padding: const EdgeInsets.all(16), children: [
          Text('Registrar nuevo lote', style: theme.textTheme.titleLarge),
          const Text('Asigna un lote a piezas que ya están en el almacén.'),
          const SizedBox(height: 16),
          if (_error != null) Padding(padding: const EdgeInsets.only(bottom: 8), child: Text(_error!, style: TextStyle(color: theme.colorScheme.error))),
          RecordDropdown(
            label: 'Almacén *',
            records: _warehouses,
            value: _warehouseId,
            icon: Icons.warehouse_outlined,
            onChanged: (v) {
              setState(() {
                _warehouseId = v;
                _product = null;
              });
              _search();
            },
          ),
          const SizedBox(height: 12),
          if (product == null) ...[
            TextField(
              controller: _query,
              onChanged: (_) {
                _debounce?.cancel();
                _debounce = Timer(const Duration(milliseconds: 300), _search);
              },
              decoration: const InputDecoration(hintText: 'Filtrar por nombre o código…', prefixIcon: Icon(Icons.search)),
            ),
            if (_searching) const LinearProgressIndicator(minHeight: 2),
            if (!_searching && _results.isEmpty && _warehouseId != null)
              const Padding(padding: EdgeInsets.all(16), child: Text('No hay productos con piezas sin lote en este almacén.')),
            for (final p in _results)
              ListTile(
                title: Text(p['name']?.toString() ?? ''),
                subtitle: Text('${formatNumber(p['unassigned_stock'])} sin lote'),
                onTap: () => _choose(p),
              ),
          ] else ...[
            Card(
              child: ListTile(
                title: Text(product['name']?.toString() ?? ''),
                subtitle: Text('${formatNumber(product['unassigned_stock'])} ${_unit.symbol} sin lote'),
                trailing: TextButton(onPressed: () => setState(() => _product = null), child: const Text('Cambiar')),
              ),
            ),
            const SizedBox(height: 12),
            TextField(controller: _lot, textCapitalization: TextCapitalization.characters, decoration: const InputDecoration(labelText: 'Número de lote *', hintText: 'Ej. A2391')),
            const SizedBox(height: 12),
            DateField(label: 'Caducidad', value: _expiration, clearable: true, firstDate: DateTime.now(), onChanged: (v) => setState(() => _expiration = v)),
            const SizedBox(height: 12),
            TextField(
              controller: _quantity,
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              decoration: InputDecoration(labelText: 'Cantidad *', suffixText: _unit.symbol),
            ),
            const SizedBox(height: 16),
            FilledButton(onPressed: _saving ? null : _save, child: Text(_saving ? 'Guardando…' : 'Registrar lote')),
          ],
        ]),
      ),
    );
  }
}
