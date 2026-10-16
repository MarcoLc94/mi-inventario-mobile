import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/api_client.dart';
import '../../core/catalogs.dart';
import '../../core/formatters.dart';
import '../../core/session.dart';
import '../../core/user_profile.dart';
import '../../widgets/form_fields.dart';

/// Recepción de mercancía de una compra (PATCH receive_and_invoice): registra
/// la factura del proveedor y suma las existencias recibidas.
Future<bool?> showReceiveSheet(BuildContext context, Map<String, dynamic> order) => showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (_) => _ReceiveSheet(order: order),
    );

class _Pending {
  _Pending(this.item, this.unit);
  final Map<String, dynamic> item;
  final Unit unit;
  final quantity = TextEditingController();
  final lot = TextEditingController();
  String? expiration;

  num get ordered => toNum(item['quantity']) ?? 0;
  num get received => toNum(item['received_quantity']) ?? 0;
  num get pending => (ordered - received).clamp(0, ordered);
  bool get tracksLots => asMap(item['product'])['tracks_lots'] == true;
}

class _ReceiveSheet extends StatefulWidget {
  const _ReceiveSheet({required this.order});
  final Map<String, dynamic> order;

  @override
  State<_ReceiveSheet> createState() => _ReceiveSheetState();
}

class _ReceiveSheetState extends State<_ReceiveSheet> {
  final _invoice = TextEditingController();
  late final _who = TextEditingController(text: context.read<SessionController>().profile?.displayName ?? '');
  String? _date = isoDate(DateTime.now());
  final _rows = <_Pending>[];
  bool _ready = false;
  bool _saving = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _prepare();
  }

  Future<void> _prepare() async {
    final catalogs = context.read<Catalogs>();
    for (final item in asMapList(widget.order['purchase_order_items'])) {
      final unit = await catalogs.unit(asMap(item['product'])['base_unit']?.toString());
      final row = _Pending(item, unit);
      if (row.pending > 0) row.quantity.text = row.pending.toString().replaceAll(RegExp(r'\.0$'), '');
      _rows.add(row);
    }
    if (mounted) setState(() => _ready = true);
  }

  Future<void> _save() async {
    final items = <Map<String, dynamic>>[];
    String? message;
    if (_invoice.text.trim().isEmpty) message = 'Escribe el número de factura o remisión del proveedor.';
    for (final row in _rows) {
      if (message != null) break;
      final quantity = num.tryParse(row.quantity.text.trim()) ?? 0;
      if (quantity <= 0) continue;
      if (!row.unit.accepts(quantity)) {
        message = '${asMap(row.item['product'])['name']}: ${row.unit.precisionMessage}';
      } else if (quantity > row.pending) {
        message = '${asMap(row.item['product'])['name']}: solo faltan ${formatNumber(row.pending)} por recibir.';
      } else if (row.tracksLots && row.lot.text.trim().isEmpty) {
        message = 'Indica el lote recibido de ${asMap(row.item['product'])['name']}.';
      } else {
        items.add({
          'id': row.item['id'],
          'received_quantity': quantity,
          if (row.tracksLots) 'lot_number': row.lot.text.trim(),
          if (row.tracksLots && row.expiration != null) 'expiration_date': row.expiration,
        });
      }
    }
    message ??= items.isEmpty ? 'Captura al menos una cantidad mayor a cero.' : null;
    if (message != null) {
      setState(() => _error = message);
      return;
    }
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      await context.read<ApiClient>().patch('/purchase_orders/${widget.order['id']}/receive_and_invoice', {
        'receive_data': {'invoice_number': _invoice.text.trim(), 'invoice_date': _date, 'who_receipt': _who.text.trim(), 'items': items},
      });
      if (mounted) Navigator.pop(context, true);
    } catch (error) {
      if (mounted) setState(() => _error = error.toString());
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
      child: SizedBox(
        height: MediaQuery.of(context).size.height * .9,
        child: !_ready
            ? const Center(child: CircularProgressIndicator())
            : ListView(padding: const EdgeInsets.all(16), children: [
                Text('Recibir mercancía', style: theme.textTheme.titleLarge),
                const Text('Las existencias se suman al almacén de cada partida.'),
                const SizedBox(height: 12),
                if (_error != null) Padding(padding: const EdgeInsets.only(bottom: 8), child: Text(_error!, style: TextStyle(color: theme.colorScheme.error))),
                TextField(controller: _invoice, decoration: const InputDecoration(labelText: 'Factura o remisión del proveedor *')),
                const SizedBox(height: 12),
                DateField(label: 'Fecha de la factura', value: _date, onChanged: (v) => setState(() => _date = v)),
                const SizedBox(height: 12),
                TextField(controller: _who, decoration: const InputDecoration(labelText: 'Recibió')),
                const SizedBox(height: 16),
                for (final row in _rows)
                  Card(
                    margin: const EdgeInsets.only(bottom: 8),
                    child: Padding(
                      padding: const EdgeInsets.all(12),
                      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                        Text(asMap(row.item['product'])['name']?.toString() ?? '', style: theme.textTheme.titleSmall),
                        Text('Pedido ${row.unit.format(row.ordered)} · recibido ${formatNumber(row.received)} · faltan ${formatNumber(row.pending)}', style: theme.textTheme.bodySmall),
                        if (row.pending > 0) ...[
                          const SizedBox(height: 8),
                          TextField(
                            controller: row.quantity,
                            keyboardType: const TextInputType.numberWithOptions(decimal: true),
                            decoration: InputDecoration(labelText: 'Recibir ahora', suffixText: row.unit.symbol),
                          ),
                          if (row.tracksLots) ...[
                            const SizedBox(height: 8),
                            TextField(controller: row.lot, decoration: const InputDecoration(labelText: 'Lote *')),
                            const SizedBox(height: 8),
                            DateField(label: 'Caducidad', value: row.expiration, clearable: true, onChanged: (v) => setState(() => row.expiration = v)),
                          ],
                        ] else
                          const Padding(padding: EdgeInsets.only(top: 4), child: Text('Completa')),
                      ]),
                    ),
                  ),
                const SizedBox(height: 8),
                FilledButton(onPressed: _saving ? null : _save, child: Text(_saving ? 'Registrando…' : 'Confirmar recepción')),
              ]),
      ),
    );
  }
}
