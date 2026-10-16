import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/api_client.dart';
import '../../core/catalogs.dart';
import '../../core/formatters.dart';
import '../../core/user_profile.dart';
import '../../widgets/async_states.dart';
import '../../widgets/form_fields.dart';
import 'return_kind.dart';

class _ReturnLine {
  _ReturnLine(this.item, this.unit, this.condition);
  final Map<String, dynamic> item;
  final Unit unit;
  final quantity = TextEditingController();
  final lot = TextEditingController();
  String condition;

  num get sold => toNum(item['quantity']) ?? 0;
  num get value => num.tryParse(quantity.text.trim()) ?? 0;
  num get unitPrice => toNum(item['unit_price']) ?? 0;
}

/// Nueva devolución: se elige el proveedor o cliente, la compra o venta y las
/// cantidades a devolver de cada partida.
class NewReturnScreen extends StatefulWidget {
  const NewReturnScreen({super.key, required this.kind});
  final ReturnKind kind;

  @override
  State<NewReturnScreen> createState() => _NewReturnScreenState();
}

class _NewReturnScreenState extends State<NewReturnScreen> {
  final _number = TextEditingController(text: 'DEV-${DateTime.now().millisecondsSinceEpoch}');
  final _notes = TextEditingController();
  String? _date = isoDate(DateTime.now());
  String _reason = 'other';
  List<Map<String, dynamic>> _partners = [];
  List<Map<String, dynamic>> _documents = [];
  int? _partnerId;
  Map<String, dynamic>? _document;
  final _lines = <_ReturnLine>[];
  bool _loading = true;
  bool _loadingDocs = false;
  Object? _loadError;
  bool _saving = false;
  String? _error;

  ReturnKind get kind => widget.kind;

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
      final partners = await kind.partners(context.read<ApiClient>());
      if (mounted) setState(() => _partners = partners);
    } catch (error) {
      if (mounted) setState(() => _loadError = error);
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _selectPartner(int? id) async {
    setState(() {
      _partnerId = id;
      _document = null;
      _documents = [];
      _lines.clear();
      _loadingDocs = id != null;
    });
    if (id == null) return;
    try {
      final docs = await kind.documents(context.read<ApiClient>(), id);
      if (mounted) setState(() => _documents = docs);
    } catch (error) {
      if (mounted) showError(context, error);
    } finally {
      if (mounted) setState(() => _loadingDocs = false);
    }
  }

  Future<void> _selectDocument(Map<String, dynamic>? doc) async {
    final catalogs = context.read<Catalogs>();
    final lines = <_ReturnLine>[];
    for (final item in asMapList(doc?[kind.documentItemsKey])) {
      if (item['product_id'] == null) continue;
      lines.add(_ReturnLine(item, await catalogs.unit(asMap(item['product'])['base_unit']?.toString()), kind.conditions.keys.first));
    }
    if (mounted) {
      setState(() {
        _document = doc;
        _lines
          ..clear()
          ..addAll(lines);
      });
    }
  }

  num get _ivaFactor => 1 + (toNum(_document?['iva_rate']) ?? 0.16);
  num get _total => _lines.fold<num>(0, (sum, l) => sum + l.value * l.unitPrice * (kind.isSupplier ? _ivaFactor : 1));

  Future<void> _save() async {
    final chosen = _lines.where((l) => l.value > 0).toList();
    String? message;
    if (_partnerId == null || _document == null || _date == null || _number.text.trim().isEmpty) {
      message = 'Completa el folio, la fecha, el ${kind.partnerLabel.toLowerCase()} y la ${kind.documentLabel.toLowerCase()}.';
    } else if (chosen.isEmpty) {
      message = 'Captura al menos una cantidad a devolver.';
    } else {
      for (final line in chosen) {
        if (!line.unit.accepts(line.value)) {
          message = '${asMap(line.item['product'])['name']}: ${line.unit.precisionMessage}';
        } else if (line.value > line.sold) {
          message = '${asMap(line.item['product'])['name']}: no puedes devolver más de ${formatNumber(line.sold)}.';
        }
        if (message != null) break;
      }
    }
    if (message != null) {
      setState(() => _error = message);
      return;
    }
    final payload = {
      'return_number': _number.text.trim(),
      kind.documentIdKey: _document!['id'],
      if (!kind.isSupplier) 'client_id': _partnerId,
      'return_date': _date,
      'status': 'pending',
      kind.totalKey: double.parse(_total.toStringAsFixed(2)),
      'reason': _reason,
      // SupplierReturn no tiene columna de notas.
      if (!kind.isSupplier) 'notes': _notes.text.trim(),
      kind.itemsAttributesKey: [
        for (final line in chosen)
          {
            'product_id': line.item['product_id'],
            if (!kind.isSupplier) 'sale_order_item_id': line.item['id'],
            'quantity': line.value,
            'reason': '',
            'condition': line.condition,
            if (kind.isSupplier) 'credit_amount': double.parse((line.value * line.unitPrice * _ivaFactor).toStringAsFixed(2)),
            if (line.lot.text.trim().isNotEmpty) 'lot_number': line.lot.text.trim(),
          },
      ],
    };
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      await context.read<ApiClient>().post(kind.endpoint, {kind.paramKey: payload});
      if (!mounted) return;
      showMessage(context, 'Devolución creada');
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
      appBar: AppBar(title: const Text('Nueva devolución')),
      body: _loading
          ? const LoadingView()
          : _loadError != null
              ? ErrorView(error: _loadError!, onRetry: _load)
              : ListView(padding: const EdgeInsets.fromLTRB(16, 16, 16, 120), children: [
                  if (_error != null) Padding(padding: const EdgeInsets.only(bottom: 12), child: Text(_error!, style: TextStyle(color: theme.colorScheme.error))),
                  TextField(controller: _number, decoration: const InputDecoration(labelText: 'Folio *')),
                  const SizedBox(height: 12),
                  DateField(label: 'Fecha *', value: _date, onChanged: (v) => setState(() => _date = v)),
                  const SizedBox(height: 12),
                  RecordDropdown(label: '${kind.partnerLabel} *', records: _partners, value: _partnerId, onChanged: _selectPartner),
                  const SizedBox(height: 12),
                  if (_loadingDocs) const LinearProgressIndicator(),
                  if (_partnerId != null && !_loadingDocs)
                    _documents.isEmpty
                        ? Text('No hay ${kind.isSupplier ? 'compras recibidas' : 'ventas'} para devolver.', style: theme.textTheme.bodySmall)
                        : DropdownButtonFormField<int>(
                            initialValue: (_document?['id'] as num?)?.toInt(),
                            isExpanded: true,
                            decoration: InputDecoration(labelText: '${kind.documentLabel} *'),
                            items: [
                              for (final d in _documents)
                                DropdownMenuItem(
                                  value: (d['id'] as num).toInt(),
                                  child: Text('${d['order_number'] ?? '#${d['id']}'} · ${formatDate(d['order_date'])}', overflow: TextOverflow.ellipsis),
                                ),
                            ],
                            onChanged: (v) => _selectDocument(_documents.where((d) => d['id'] == v).firstOrNull),
                          ),
                  const SizedBox(height: 12),
                  DropdownButtonFormField<String>(
                    initialValue: _reason,
                    decoration: const InputDecoration(labelText: 'Motivo'),
                    items: [for (final e in kind.reasons.entries) DropdownMenuItem(value: e.key, child: Text(e.value))],
                    onChanged: (v) => setState(() => _reason = v ?? 'other'),
                  ),
                  if (!kind.isSupplier) ...[
                    const SizedBox(height: 12),
                    TextField(controller: _notes, maxLines: 2, decoration: const InputDecoration(labelText: 'Notas')),
                  ],
                  if (_lines.isNotEmpty) ...[
                    const SizedBox(height: 20),
                    Text('¿Qué se devuelve?', style: theme.textTheme.titleMedium),
                    const SizedBox(height: 8),
                    for (final line in _lines)
                      Card(
                        margin: const EdgeInsets.only(bottom: 8),
                        child: Padding(
                          padding: const EdgeInsets.all(12),
                          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                            Text(asMap(line.item['product'])['name']?.toString() ?? line.item['product_name']?.toString() ?? '', style: theme.textTheme.titleSmall),
                            Text('${kind.isSupplier ? 'Comprado' : 'Vendido'}: ${line.unit.format(line.sold)} · ${formatMoney(line.unitPrice)} c/u', style: theme.textTheme.bodySmall),
                            const SizedBox(height: 8),
                            Row(children: [
                              Expanded(
                                child: TextField(
                                  controller: line.quantity,
                                  keyboardType: const TextInputType.numberWithOptions(decimal: true),
                                  decoration: InputDecoration(labelText: 'Devolver', suffixText: line.unit.symbol),
                                  onChanged: (_) => setState(() {}),
                                ),
                              ),
                              const SizedBox(width: 8),
                              Expanded(
                                child: DropdownButtonFormField<String>(
                                  initialValue: line.condition,
                                  decoration: const InputDecoration(labelText: 'Condición'),
                                  items: [for (final e in kind.conditions.entries) DropdownMenuItem(value: e.key, child: Text(e.value))],
                                  onChanged: (v) => setState(() => line.condition = v ?? kind.conditions.keys.first),
                                ),
                              ),
                            ]),
                            if (asMap(line.item['product'])['tracks_lots'] == true) ...[
                              const SizedBox(height: 8),
                              TextField(controller: line.lot, decoration: const InputDecoration(labelText: 'Lote')),
                            ],
                          ]),
                        ),
                      ),
                    Align(
                      alignment: Alignment.centerRight,
                      child: Text('${kind.isSupplier ? 'Crédito' : 'Reembolso'} estimado: ${formatMoney(_total)}', style: theme.textTheme.titleSmall),
                    ),
                  ],
                ]),
      bottomNavigationBar: _loading || _loadError != null
          ? null
          : SafeArea(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: FilledButton(onPressed: _saving ? null : _save, child: Text(_saving ? 'Guardando…' : 'Crear devolución')),
              ),
            ),
    );
  }
}
