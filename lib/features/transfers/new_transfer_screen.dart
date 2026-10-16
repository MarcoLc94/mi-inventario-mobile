import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/api_client.dart';
import '../../core/catalogs.dart';
import '../../core/formatters.dart';
import '../../widgets/async_states.dart';
import '../../widgets/form_fields.dart';
import '../../widgets/product_picker.dart';

class _Item {
  _Item(this.product, this.unit);
  final Map<String, dynamic> product;
  final Unit unit;
  final quantity = TextEditingController();
  final lot = TextEditingController();
  num get available => toNum(product['available_stock'] ?? product['stock']) ?? 0;
}

/// Nueva transferencia entre almacenes. Se crea como borrador.
class NewTransferScreen extends StatefulWidget {
  const NewTransferScreen({super.key});

  @override
  State<NewTransferScreen> createState() => _NewTransferScreenState();
}

class _NewTransferScreenState extends State<NewTransferScreen> {
  List<Map<String, dynamic>> _warehouses = [];
  int? _from;
  int? _to;
  String? _date = isoDate(DateTime.now());
  final _notes = TextEditingController();
  final _items = <_Item>[];
  bool _loading = true;
  Object? _loadError;
  bool _saving = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _loadError = null;
    });
    try {
      final warehouses = await context.read<Catalogs>().activeWarehouses();
      if (mounted) setState(() => _warehouses = warehouses);
    } catch (error) {
      if (mounted) setState(() => _loadError = error);
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _addProduct() async {
    if (_from == null) {
      setState(() => _error = 'Primero elige el almacén de origen.');
      return;
    }
    final picked = await pickProduct(context, warehouseId: _from, title: 'Productos en el almacén de origen');
    if (picked == null || !mounted) return;
    if (_items.any((i) => i.product['id'] == picked['id'])) {
      showMessage(context, 'Ese producto ya está en la lista.');
      return;
    }
    final unit = await context.read<Catalogs>().unit(picked['base_unit']?.toString());
    setState(() {
      _items.add(_Item(picked, unit));
      _error = null;
    });
  }

  Future<void> _save() async {
    String? message;
    if (_from == null || _to == null || _date == null) {
      message = 'Elige origen, destino y fecha.';
    } else if (_from == _to) {
      message = 'El almacén de destino debe ser distinto al de origen.';
    } else if (_items.isEmpty) {
      message = 'Agrega al menos un producto.';
    } else {
      for (final item in _items) {
        final quantity = num.tryParse(item.quantity.text.trim());
        if (quantity == null || !item.unit.accepts(quantity)) {
          message = '${item.product['name']}: ${quantity == null || quantity <= 0 ? 'la cantidad debe ser mayor que cero.' : item.unit.precisionMessage}';
          break;
        }
        if (quantity > item.available) {
          message = '${item.product['name']}: solo hay ${formatNumber(item.available)} disponibles.';
          break;
        }
      }
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
      await context.read<ApiClient>().post('/inventory_transfers', {
        'inventory_transfer': {
          'from_warehouse_id': _from,
          'to_warehouse_id': _to,
          'transfer_date': _date,
          'status': 'draft',
          'notes': _notes.text.trim(),
          'inventory_transfer_items_attributes': [
            for (final item in _items)
              {
                'product_id': item.product['id'],
                'quantity': num.parse(item.quantity.text.trim()),
                if (item.lot.text.trim().isNotEmpty) 'lot_number': item.lot.text.trim(),
              },
          ],
        },
      });
      if (!mounted) return;
      showMessage(context, 'Transferencia creada como borrador');
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
      appBar: AppBar(title: const Text('Nueva transferencia')),
      body: _loading
          ? const LoadingView()
          : _loadError != null
              ? ErrorView(error: _loadError!, onRetry: _load)
              : ListView(padding: const EdgeInsets.fromLTRB(16, 16, 16, 120), children: [
                  if (_error != null) Padding(padding: const EdgeInsets.only(bottom: 12), child: Text(_error!, style: TextStyle(color: theme.colorScheme.error))),
                  RecordDropdown(
                    label: 'Almacén de origen *',
                    records: _warehouses,
                    value: _from,
                    icon: Icons.outbox_outlined,
                    onChanged: (v) => setState(() {
                      if (v != _from) _items.clear();
                      _from = v;
                    }),
                  ),
                  const SizedBox(height: 12),
                  RecordDropdown(
                    label: 'Almacén de destino *',
                    records: _warehouses.where((w) => w['id'] != _from).toList(),
                    value: _to,
                    icon: Icons.move_to_inbox_outlined,
                    onChanged: (v) => setState(() => _to = v),
                  ),
                  const SizedBox(height: 12),
                  DateField(label: 'Fecha *', value: _date, onChanged: (v) => setState(() => _date = v)),
                  const SizedBox(height: 12),
                  TextField(controller: _notes, maxLines: 2, decoration: const InputDecoration(labelText: 'Notas')),
                  const SizedBox(height: 20),
                  Text('Productos', style: theme.textTheme.titleMedium),
                  const SizedBox(height: 8),
                  for (final item in _items)
                    Card(
                      margin: const EdgeInsets.only(bottom: 8),
                      child: Padding(
                        padding: const EdgeInsets.all(12),
                        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                          Row(children: [
                            Expanded(child: Text(item.product['name']?.toString() ?? '', style: theme.textTheme.titleSmall)),
                            IconButton(tooltip: 'Quitar', icon: const Icon(Icons.delete_outline), onPressed: () => setState(() => _items.remove(item))),
                          ]),
                          Text('Disponible: ${item.unit.format(item.available)}', style: theme.textTheme.bodySmall),
                          const SizedBox(height: 8),
                          TextField(
                            controller: item.quantity,
                            keyboardType: const TextInputType.numberWithOptions(decimal: true),
                            decoration: InputDecoration(labelText: 'Cantidad', suffixText: item.unit.symbol),
                          ),
                          if (item.product['tracks_lots'] == true) ...[
                            const SizedBox(height: 8),
                            TextField(controller: item.lot, decoration: const InputDecoration(labelText: 'Lote', helperText: 'Vacío: sale primero el que caduca antes')),
                          ],
                        ]),
                      ),
                    ),
                  OutlinedButton.icon(onPressed: _addProduct, icon: const Icon(Icons.add), label: const Text('Agregar producto')),
                ]),
      bottomNavigationBar: _loading || _loadError != null
          ? null
          : SafeArea(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: FilledButton(onPressed: _saving ? null : _save, child: Text(_saving ? 'Guardando…' : 'Crear transferencia')),
              ),
            ),
    );
  }
}
