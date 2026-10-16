import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/api_client.dart';
import '../../core/catalogs.dart';
import '../../core/formatters.dart';
import '../../core/user_profile.dart';
import '../../widgets/async_states.dart';
import '../../widgets/form_fields.dart';
import '../../widgets/product_picker.dart';

class _Row {
  int? warehouseId;
  Map<String, dynamic>? product;
  Unit unit = Unit.piece;
  num? stock;
  bool remove = false;
  final amount = TextEditingController();
  final reason = TextEditingController();
  final lot = TextEditingController();
  String? expiration;

  bool get tracksLots => product?['tracks_lots'] == true;
}

/// Nuevo ajuste: se guarda pendiente y las existencias cambian al aprobarlo.
class NewAdjustmentScreen extends StatefulWidget {
  const NewAdjustmentScreen({super.key});

  @override
  State<NewAdjustmentScreen> createState() => _NewAdjustmentScreenState();
}

class _NewAdjustmentScreenState extends State<NewAdjustmentScreen> {
  final _number = TextEditingController(text: 'ADJ-${DateTime.now().millisecondsSinceEpoch}');
  final _notes = TextEditingController();
  String? _date = isoDate(DateTime.now());
  final _rows = <_Row>[_Row()];
  List<Map<String, dynamic>> _warehouses = [];
  bool _loading = true;
  Object? _loadError;
  bool _saving = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _loadWarehouses();
  }

  Future<void> _loadWarehouses() async {
    setState(() {
      _loading = true;
      _loadError = null;
    });
    try {
      final warehouses = await context.read<Catalogs>().activeWarehouses();
      if (!mounted) return;
      setState(() {
        _warehouses = warehouses;
        if (warehouses.length == 1) _rows.first.warehouseId = (warehouses.first['id'] as num).toInt();
      });
    } catch (error) {
      if (mounted) setState(() => _loadError = error);
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _pickProduct(_Row row) async {
    final picked = await pickProduct(context);
    if (picked == null || !mounted) return;
    final unit = await context.read<Catalogs>().unit(picked['base_unit']?.toString());
    setState(() {
      row.product = picked;
      row.unit = unit;
      row.stock = null;
    });
    await _loadStock(row);
  }

  Future<void> _loadStock(_Row row) async {
    final product = row.product;
    if (product == null || row.warehouseId == null) return;
    try {
      final detail = asMap(await context.read<ApiClient>().get('/products/${product['id']}'));
      final inventory = asMapList(detail['stock_by_warehouse']).where((w) => w['warehouse_id'] == row.warehouseId).firstOrNull;
      if (mounted) setState(() => row.stock = toNum(inventory?['stock']) ?? 0);
    } catch (_) {
      if (mounted) setState(() => row.stock = null);
    }
  }

  String? _rowError(_Row row, Set<String> pairs) {
    final amount = num.tryParse(row.amount.text.trim());
    final pair = '${row.warehouseId}:${row.product?['id']}';
    if (row.warehouseId == null) return 'Selecciona un almacén.';
    if (row.product == null) return 'Selecciona un producto.';
    if (row.stock == null) return 'Consulta de nuevo las existencias antes de continuar.';
    if (amount == null || !row.unit.accepts(amount)) {
      return row.unit.decimals > 0 ? 'Escribe una cantidad mayor a cero con máximo ${row.unit.decimals} decimales.' : 'Escribe una cantidad entera mayor a cero.';
    }
    if (row.remove && amount > row.stock!) return 'Solo hay ${formatNumber(row.stock)} unidades en este almacén.';
    if (row.reason.text.trim().isEmpty) return 'Indica el motivo del ajuste.';
    if (!pairs.add(pair)) return 'Este producto ya está incluido para el mismo almacén.';
    return null;
  }

  Future<void> _save() async {
    if (_number.text.trim().isEmpty || _date == null) {
      setState(() => _error = 'Completa el folio, la fecha y al menos un producto.');
      return;
    }
    final pairs = <String>{};
    for (var i = 0; i < _rows.length; i++) {
      final message = _rowError(_rows[i], pairs);
      if (message != null) {
        setState(() => _error = 'Producto ${i + 1}: $message');
        return;
      }
    }
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      await context.read<ApiClient>().post('/inventory_adjustments', {
        'adjustment_number': _number.text.trim(),
        'adjustment_date': _date,
        'status': 'pending',
        'notes': _notes.text.trim(),
        'adjustment_items_attributes': [
          for (final row in _rows)
            {
              'product_id': row.product!['id'],
              'warehouse_id': row.warehouseId,
              'quantity': num.parse(row.amount.text.trim()) * (row.remove ? -1 : 1),
              'reason': row.reason.text.trim(),
              if (row.tracksLots && row.lot.text.trim().isNotEmpty) 'lot_number': row.lot.text.trim(),
              if (row.tracksLots && row.lot.text.trim().isNotEmpty && !row.remove && row.expiration != null) 'expiration_date': row.expiration,
            },
        ],
      });
      if (!mounted) return;
      showMessage(context, 'Ajuste creado. Queda pendiente de aprobación.');
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
      appBar: AppBar(title: const Text('Nuevo ajuste')),
      body: _loading
          ? const LoadingView(label: 'Cargando almacenes…')
          : _loadError != null
              ? ErrorView(error: _loadError!, onRetry: _loadWarehouses)
              : ListView(padding: const EdgeInsets.fromLTRB(16, 16, 16, 120), children: [
                  Card(
                    color: theme.colorScheme.secondaryContainer,
                    child: const ListTile(
                      leading: Icon(Icons.schedule),
                      title: Text('Se guardará pendiente de aprobación'),
                      subtitle: Text('Las existencias se actualizarán cuando el ajuste sea aprobado.'),
                    ),
                  ),
                  const SizedBox(height: 12),
                  if (_error != null) Padding(padding: const EdgeInsets.only(bottom: 12), child: Text(_error!, style: TextStyle(color: theme.colorScheme.error))),
                  TextField(controller: _number, decoration: const InputDecoration(labelText: 'Folio *')),
                  const SizedBox(height: 12),
                  DateField(label: 'Fecha *', value: _date, onChanged: (v) => setState(() => _date = v)),
                  const SizedBox(height: 12),
                  TextField(controller: _notes, maxLines: 2, decoration: const InputDecoration(labelText: 'Notas')),
                  const SizedBox(height: 20),
                  Text('Productos', style: theme.textTheme.titleMedium),
                  const SizedBox(height: 8),
                  for (var i = 0; i < _rows.length; i++) _rowCard(i),
                  OutlinedButton.icon(
                    onPressed: () => setState(() => _rows.add(_Row()..warehouseId = _rows.last.warehouseId)),
                    icon: const Icon(Icons.add),
                    label: const Text('Agregar producto'),
                  ),
                ]),
      bottomNavigationBar: _loading || _loadError != null
          ? null
          : SafeArea(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: FilledButton(onPressed: _saving ? null : _save, child: Text(_saving ? 'Guardando…' : 'Guardar ajuste')),
              ),
            ),
    );
  }

  Widget _rowCard(int index) {
    final row = _rows[index];
    final theme = Theme.of(context);
    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Row(children: [
            Expanded(child: Text('Producto ${index + 1}', style: theme.textTheme.titleSmall)),
            if (_rows.length > 1)
              IconButton(tooltip: 'Quitar', icon: const Icon(Icons.delete_outline), onPressed: () => setState(() => _rows.removeAt(index))),
          ]),
          RecordDropdown(
            label: 'Almacén',
            records: _warehouses,
            value: row.warehouseId,
            onChanged: (v) {
              setState(() {
                row.warehouseId = v;
                row.stock = null;
              });
              _loadStock(row);
            },
          ),
          const SizedBox(height: 8),
          OutlinedButton.icon(
            onPressed: () => _pickProduct(row),
            icon: const Icon(Icons.search),
            label: Text(row.product?['name']?.toString() ?? 'Elegir producto', overflow: TextOverflow.ellipsis),
          ),
          if (row.product != null)
            Padding(
              padding: const EdgeInsets.only(top: 4),
              child: Text(row.stock == null ? 'Consultando existencias…' : 'Existencia en el almacén: ${row.unit.format(row.stock)}', style: theme.textTheme.bodySmall),
            ),
          const SizedBox(height: 8),
          SegmentedButton<bool>(
            segments: const [
              ButtonSegment(value: false, label: Text('Agregar'), icon: Icon(Icons.add)),
              ButtonSegment(value: true, label: Text('Retirar'), icon: Icon(Icons.remove)),
            ],
            selected: {row.remove},
            onSelectionChanged: (v) => setState(() => row.remove = v.first),
          ),
          const SizedBox(height: 8),
          TextField(
            controller: row.amount,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            decoration: InputDecoration(labelText: 'Cantidad', suffixText: row.unit.symbol),
          ),
          const SizedBox(height: 8),
          TextField(controller: row.reason, decoration: const InputDecoration(labelText: 'Motivo', hintText: 'Ej. Merma, conteo físico')),
          if (row.tracksLots) ...[
            const SizedBox(height: 8),
            TextField(controller: row.lot, decoration: InputDecoration(labelText: 'Lote', helperText: row.remove ? 'Vacío: sale primero el que caduca antes' : null)),
            if (!row.remove) ...[
              const SizedBox(height: 8),
              DateField(label: 'Caducidad del lote', value: row.expiration, clearable: true, onChanged: (v) => setState(() => row.expiration = v)),
            ],
          ],
        ]),
      ),
    );
  }
}
