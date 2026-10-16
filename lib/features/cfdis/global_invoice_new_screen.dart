import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../../core/api_client.dart';
import '../../core/formatters.dart';
import '../../core/ids.dart';
import '../../core/user_profile.dart';
import '../../widgets/form_fields.dart';
import 'cfdi_catalogs.dart';

String _iso(DateTime d) => isoDate(d);
DateTime _lastDayOf(int year, int month) => DateTime(year, month + 1, 0);

/// Rango del periodo según la periodicidad (igual que web/globalPeriod.ts).
/// Semanal y quincenal nunca cruzan de mes: el SAT pide un mes por factura.
({String start, String end})? periodRange(String periodicity, String? day, DateTime? month, String half, [DateTime? today]) {
  final now = today ?? DateTime.now();
  if (periodicity == '01') return day == null ? null : (start: day, end: day);
  if (periodicity == '02') {
    if (day == null) return null;
    final start = DateTime.parse(day);
    var end = start.add(const Duration(days: 6));
    final monthEnd = _lastDayOf(start.year, start.month);
    if (end.isAfter(monthEnd)) end = monthEnd;
    if (end.isAfter(now)) end = DateTime(now.year, now.month, now.day);
    return (start: day, end: _iso(end));
  }
  if (month == null) return null;
  if (periodicity == '03') {
    return half == '1'
        ? (start: _iso(DateTime(month.year, month.month, 1)), end: _iso(DateTime(month.year, month.month, 15)))
        : (start: _iso(DateTime(month.year, month.month, 16)), end: _iso(_lastDayOf(month.year, month.month)));
  }
  if (periodicity == '05') {
    final first = month.month.isOdd ? month.month : month.month - 1;
    return (start: _iso(DateTime(month.year, first, 1)), end: _iso(_lastDayOf(month.year, first + 1)));
  }
  return (start: _iso(DateTime(month.year, month.month, 1)), end: _iso(_lastDayOf(month.year, month.month)));
}

/// Emitir factura global: elige el periodo, revisa los tickets y timbra.
class GlobalInvoiceNewScreen extends StatefulWidget {
  const GlobalInvoiceNewScreen({super.key});

  @override
  State<GlobalInvoiceNewScreen> createState() => _GlobalInvoiceNewScreenState();
}

class _GlobalInvoiceNewScreenState extends State<GlobalInvoiceNewScreen> {
  String _periodicity = '04';
  late String? _day = _iso(DateTime.now().subtract(const Duration(days: 1)));
  DateTime _month = DateTime(DateTime.now().year, DateTime.now().month - 1);
  String _half = '1';
  String? _paymentForm;
  Map<String, dynamic>? _preview;
  String? _previewError;
  bool _loading = false;
  bool _busy = false;
  String _key = newRequestKey();
  int _request = 0;

  ({String start, String end})? get _range => periodRange(_periodicity, _day, _month, _half);

  @override
  void initState() {
    super.initState();
    _loadPreview();
  }

  Future<void> _loadPreview() async {
    final range = _range;
    final request = ++_request;
    setState(() {
      _preview = null;
      _previewError = null;
      _key = newRequestKey();
      _loading = range != null;
    });
    if (range == null) return;
    try {
      final data = asMap(await context.read<ApiClient>().get('/global_invoices/preview', query: {'periodicity': _periodicity, 'period_start': range.start, 'period_end': range.end}));
      if (mounted && request == _request) setState(() => _preview = data);
    } catch (error) {
      if (mounted && request == _request) setState(() => _previewError = error.toString());
    } finally {
      if (mounted && request == _request) setState(() => _loading = false);
    }
  }

  Future<void> _emit() async {
    final range = _range;
    if (range == null || _preview == null) return;
    setState(() => _busy = true);
    try {
      final invoice = asMap(await context.read<ApiClient>().post('/global_invoices', {
        'periodicity': _periodicity,
        'period_start': range.start,
        'period_end': range.end,
        'payment_form': ?_paymentForm,
        'idempotency_key': _key,
      }));
      if (!mounted) return;
      showMessage(context, invoice['status'] == 'stamped' ? 'Factura global ${cfdiFolio(invoice)} timbrada' : 'La factura global se guardó pero no se pudo timbrar. Revisa el error y reintenta.');
      context.pushReplacement('/cfdis/factura-global/${invoice['id']}');
    } catch (error) {
      if (mounted) {
        showMessage(context, error.toString());
        setState(() => _busy = false);
      }
    }
  }

  Future<void> _pickMonth() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _month,
      firstDate: DateTime(DateTime.now().year - 2),
      lastDate: DateTime.now(),
      helpText: 'Elige cualquier día del mes',
    );
    if (picked != null) {
      setState(() => _month = DateTime(picked.year, picked.month));
      _loadPreview();
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final usesDay = _periodicity == '01' || _periodicity == '02';
    final range = _range;
    final preview = _preview;
    final tickets = asMapList(preview?['tickets']);
    return Scaffold(
      appBar: AppBar(title: const Text('Emitir factura global')),
      body: ListView(padding: const EdgeInsets.all(16), children: [
        const Text('Incluye las ventas del punto de venta que no se facturaron en el periodo. Se emite a "Público en general" (XAXX010101000) con un concepto por ticket.'),
        const SizedBox(height: 8),
        const CfdiSandboxBanner(),
        const SizedBox(height: 8),
        DropdownButtonFormField<String>(
          initialValue: _periodicity,
          decoration: const InputDecoration(labelText: 'Periodicidad'),
          items: [for (final e in globalPeriodicities.entries) DropdownMenuItem(value: e.key, child: Text(e.value))],
          onChanged: (v) {
            setState(() => _periodicity = v ?? '04');
            _loadPreview();
          },
        ),
        const SizedBox(height: 12),
        if (usesDay)
          DateField(
            label: _periodicity == '01' ? 'Día' : 'Inicio de la semana',
            value: _day,
            lastDate: DateTime.now(),
            onChanged: (v) {
              setState(() => _day = v);
              _loadPreview();
            },
          )
        else
          InkWell(
            onTap: _pickMonth,
            child: InputDecorator(
              decoration: const InputDecoration(labelText: 'Mes', prefixIcon: Icon(Icons.calendar_month_outlined)),
              child: Text('${_month.month.toString().padLeft(2, '0')}/${_month.year}'),
            ),
          ),
        if (_periodicity == '03') ...[
          const SizedBox(height: 12),
          SegmentedButton<String>(
            segments: const [ButtonSegment(value: '1', label: Text('1 al 15')), ButtonSegment(value: '2', label: Text('16 al fin'))],
            selected: {_half},
            onSelectionChanged: (v) {
              setState(() => _half = v.first);
              _loadPreview();
            },
          ),
        ],
        if (range != null) Padding(padding: const EdgeInsets.only(top: 8), child: Text('Periodo: ${formatDate(range.start)} – ${formatDate(range.end)}', style: theme.textTheme.bodySmall)),
        const SizedBox(height: 12),
        DropdownButtonFormField<String?>(
          initialValue: _paymentForm,
          isExpanded: true,
          decoration: const InputDecoration(labelText: 'Forma de pago'),
          items: [
            DropdownMenuItem<String?>(value: null, child: Text('Automática${preview?['payment_form'] != null ? ' (${satPaymentForms[preview!['payment_form']] ?? preview['payment_form']})' : ''}')),
            for (final e in satPaymentForms.entries) DropdownMenuItem<String?>(value: e.key, child: Text(e.value, overflow: TextOverflow.ellipsis)),
          ],
          onChanged: (v) => setState(() => _paymentForm = v),
        ),
        const SizedBox(height: 16),
        if (_loading) const LinearProgressIndicator(),
        if (_previewError != null) Text(_previewError!, style: TextStyle(color: theme.colorScheme.error)),
        if (preview != null)
          SectionCard(title: 'Tickets sin facturar (${preview['tickets_count'] ?? tickets.length})', children: [
            if (tickets.isEmpty) const Padding(padding: EdgeInsets.fromLTRB(16, 0, 16, 8), child: Text('No hay ventas pendientes de facturar en este periodo.')),
            for (final t in tickets.take(50))
              ListTile(dense: true, title: Text(t['folio']?.toString() ?? ''), subtitle: Text(formatDate(t['date'])), trailing: Text(formatMoney(t['total']))),
            if (tickets.length > 50) Padding(padding: const EdgeInsets.all(16), child: Text('y ${tickets.length - 50} tickets más')),
            InfoRow('Subtotal', formatMoney(preview['subtotal'])),
            InfoRow('IVA', formatMoney(preview['iva'])),
            InfoRow('Total', formatMoney(preview['total'])),
          ]),
        const SizedBox(height: 80),
      ]),
      bottomNavigationBar: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: FilledButton(
            onPressed: _busy || preview == null || tickets.isEmpty ? null : _emit,
            child: Text(_busy ? 'Timbrando…' : 'Emitir y timbrar'),
          ),
        ),
      ),
    );
  }
}
