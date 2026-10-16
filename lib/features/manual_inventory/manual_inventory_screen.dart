import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/api_client.dart';
import '../../core/catalogs.dart';
import '../../core/formatters.dart';
import '../../core/ids.dart';
import '../../core/user_profile.dart';
import '../../widgets/async_states.dart';
import '../../widgets/form_fields.dart';
import '../../widgets/product_picker.dart';
import 'receipts_screen.dart';

class _Line {
  _Line(this.product, this.unit);
  final Map<String, dynamic> product;
  final Unit unit;
  final quantity = TextEditingController();
  final lot = TextEditingController();
  String? expiration;
  String presentation = 'base';

  List<Map<String, dynamic>> get presentations => asMapList(product['presentations']).where((p) => p['ref'] != 'base').toList();
  bool get tracksLots => product['tracks_lots'] == true;

  /// La API trabaja en unidad base: se convierte con el redondeo del servidor.
  num? get baseQuantity {
    final value = num.tryParse(quantity.text.trim());
    if (value == null) return null;
    final factor = toNum(presentations.where((p) => p['ref'] == presentation).firstOrNull?['factor']) ?? 1;
    final scale = [1, 10, 100, 1000, 10000][unit.decimals.clamp(0, 4)];
    return (value * factor * scale).round() / scale;
  }
}

/// Entradas y salidas manuales (POST /manual_inventory_movements). Al
/// confirmar, queda un comprobante en PDF.
class ManualInventoryScreen extends StatefulWidget {
  const ManualInventoryScreen({super.key, required this.direction});
  final String direction;

  @override
  State<ManualInventoryScreen> createState() => _ManualInventoryScreenState();
}

class _ManualInventoryScreenState extends State<ManualInventoryScreen> {
  final _requestKey = newRequestKey();
  final _reason = TextEditingController();
  final _reference = TextEditingController();
  final _notes = TextEditingController();
  final _lines = <_Line>[];
  List<Map<String, dynamic>> _warehouses = [];
  int? _warehouseId;
  bool _saving = false;
  String? _error;
  Map<String, dynamic>? _saved;

  bool get _entry => widget.direction == 'IN';

  @override
  void initState() {
    super.initState();
    context.read<Catalogs>().activeWarehouses().then((w) {
      if (!mounted) return;
      setState(() {
        _warehouses = w;
        if (w.length == 1) _warehouseId = (w.first['id'] as num).toInt();
      });
    }).catchError((Object error) {
      if (mounted) setState(() => _error = error.toString());
    });
  }

  Future<void> _add() async {
    final picked = await pickProduct(context);
    if (picked == null || !mounted) return;
    final unit = await context.read<Catalogs>().unit(picked['base_unit']?.toString());
    setState(() => _lines.add(_Line(picked, unit)));
  }

  Future<void> _save() async {
    String? message;
    if (_warehouseId == null) {
      message = 'Selecciona un almacén.';
    } else if (_reason.text.trim().isEmpty) {
      message = 'Escribe el motivo.';
    } else if (_lines.isEmpty) {
      message = 'Agrega al menos un producto.';
    } else {
      for (final line in _lines) {
        final base = line.baseQuantity;
        if (base == null || !line.unit.accepts(base)) {
          message = '${line.product['name']}: ${base == null || base <= 0 ? 'la cantidad debe ser mayor que cero.' : line.unit.precisionMessage}';
          break;
        }
        if (_entry && line.tracksLots && line.lot.text.trim().isEmpty) {
          message = '${line.product['name']}: indica el lote que entra.';
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
      final receipt = await context.read<ApiClient>().post('/manual_inventory_movements', {
        'direction': widget.direction,
        'warehouse_id': _warehouseId,
        'reason': _reason.text.trim(),
        'reference_number': _reference.text.trim(),
        'notes': _notes.text.trim(),
        'request_key': _requestKey,
        'items': [
          for (final line in _lines)
            {
              'product_id': line.product['id'],
              'quantity': line.baseQuantity,
              if (line.tracksLots && line.lot.text.trim().isNotEmpty) 'lot_number': line.lot.text.trim(),
              if (line.tracksLots && _entry && line.expiration != null) 'expiration_date': line.expiration,
            },
        ],
      });
      if (mounted) setState(() => _saved = asMap(receipt));
    } catch (error) {
      if (mounted) setState(() => _error = error.toString());
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final title = _entry ? 'Registrar entrada' : 'Registrar salida';
    final saved = _saved;
    if (saved != null) {
      return Scaffold(
        appBar: AppBar(title: Text(title)),
        body: MessageView(
          icon: Icons.check_circle_outline,
          title: '${_entry ? 'Entrada' : 'Salida'} registrada',
          message: 'Folio ${saved['folio'] ?? ''}. Las existencias ya se actualizaron.',
          action: Column(children: [
            FilledButton.icon(onPressed: () => openReceiptPdf(context, saved), icon: const Icon(Icons.picture_as_pdf_outlined), label: const Text('Abrir comprobante')),
            const SizedBox(height: 8),
            TextButton(onPressed: () => Navigator.pop(context, true), child: const Text('Listo')),
          ]),
        ),
      );
    }
    return Scaffold(
      appBar: AppBar(title: Text(title)),
      body: ListView(padding: const EdgeInsets.fromLTRB(16, 16, 16, 120), children: [
        if (_error != null) Padding(padding: const EdgeInsets.only(bottom: 12), child: Text(_error!, style: TextStyle(color: theme.colorScheme.error))),
        RecordDropdown(label: 'Almacén *', records: _warehouses, value: _warehouseId, icon: Icons.warehouse_outlined, onChanged: (v) => setState(() => _warehouseId = v)),
        const SizedBox(height: 12),
        TextField(
          controller: _reason,
          maxLength: 250,
          decoration: InputDecoration(labelText: 'Motivo *', hintText: _entry ? 'Ej. Existencias iniciales o devolución' : 'Ej. Consumo interno o entrega'),
        ),
        TextField(controller: _reference, decoration: const InputDecoration(labelText: 'Referencia (opcional)', hintText: 'Ej. Nota o remisión')),
        const SizedBox(height: 12),
        TextField(controller: _notes, maxLines: 2, decoration: const InputDecoration(labelText: 'Notas')),
        const SizedBox(height: 20),
        Text('Productos', style: theme.textTheme.titleMedium),
        const SizedBox(height: 8),
        for (final line in _lines)
          Card(
            margin: const EdgeInsets.only(bottom: 8),
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                Row(children: [
                  Expanded(child: Text(line.product['name']?.toString() ?? '', style: theme.textTheme.titleSmall)),
                  IconButton(tooltip: 'Quitar', icon: const Icon(Icons.delete_outline), onPressed: () => setState(() => _lines.remove(line))),
                ]),
                Row(children: [
                  Expanded(
                    child: TextField(
                      controller: line.quantity,
                      keyboardType: const TextInputType.numberWithOptions(decimal: true),
                      decoration: InputDecoration(labelText: 'Cantidad', suffixText: line.presentation == 'base' ? line.unit.symbol : null),
                      onChanged: (_) => setState(() {}),
                    ),
                  ),
                  if (line.presentations.isNotEmpty) ...[
                    const SizedBox(width: 8),
                    Expanded(
                      child: DropdownButtonFormField<String>(
                        initialValue: line.presentation,
                        isExpanded: true,
                        decoration: const InputDecoration(labelText: 'En'),
                        items: [
                          DropdownMenuItem(value: 'base', child: Text(line.unit.plural)),
                          for (final p in line.presentations) DropdownMenuItem(value: p['ref'].toString(), child: Text(p['name'].toString())),
                        ],
                        onChanged: (v) => setState(() => line.presentation = v ?? 'base'),
                      ),
                    ),
                  ],
                ]),
                if (line.presentation != 'base' && line.baseQuantity != null)
                  Text('= ${line.unit.format(line.baseQuantity)}', style: theme.textTheme.bodySmall),
                if (line.tracksLots) ...[
                  const SizedBox(height: 8),
                  TextField(controller: line.lot, decoration: InputDecoration(labelText: _entry ? 'Lote *' : 'Lote', helperText: _entry ? null : 'Vacío: sale primero el que caduca antes')),
                  if (_entry) ...[
                    const SizedBox(height: 8),
                    DateField(label: 'Caducidad', value: line.expiration, clearable: true, onChanged: (v) => setState(() => line.expiration = v)),
                  ],
                ],
              ]),
            ),
          ),
        OutlinedButton.icon(onPressed: _add, icon: const Icon(Icons.add), label: const Text('Agregar producto')),
      ]),
      bottomNavigationBar: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: FilledButton(onPressed: _saving ? null : _save, child: Text(_saving ? 'Registrando…' : 'Confirmar ${_entry ? 'entrada' : 'salida'}')),
        ),
      ),
    );
  }
}
