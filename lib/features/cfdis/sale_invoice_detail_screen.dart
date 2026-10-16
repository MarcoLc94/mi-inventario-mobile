import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../../core/api_client.dart';
import '../../core/files.dart';
import '../../core/formatters.dart';
import '../../core/ids.dart';
import '../../core/user_profile.dart';
import '../../widgets/async_states.dart';
import '../../widgets/form_fields.dart';
import 'cfdi_catalogs.dart';

class SaleInvoiceDetailScreen extends StatefulWidget {
  const SaleInvoiceDetailScreen({super.key, required this.id});
  final String id;

  @override
  State<SaleInvoiceDetailScreen> createState() => _SaleInvoiceDetailScreenState();
}

class _SaleInvoiceDetailScreenState extends State<SaleInvoiceDetailScreen> {
  Map<String, dynamic>? _invoice;
  Object? _error;
  bool _busy = false;

  ApiClient get _api => context.read<ApiClient>();

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final data = asMap(await _api.get('/sale_invoices/${widget.id}'));
      if (mounted) setState(() => _invoice = data);
    } catch (error) {
      if (mounted) setState(() => _error = error);
    }
  }

  Future<void> _run(Future<dynamic> Function() action, String Function(Map<String, dynamic>) success) async {
    setState(() => _busy = true);
    try {
      final updated = asMap(await action());
      if (!mounted) return;
      setState(() => _invoice = {..._invoice!, ...updated});
      showMessage(context, success(updated));
      await _load();
    } catch (error) {
      if (mounted) showError(context, error);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _cancel() async {
    final result = await askCancellation(context);
    if (result == null) return;
    await _run(() => _api.post('/sale_invoices/${widget.id}/cancel', {'motive': result.$1, 'uuid_replacement': result.$2}),
        (d) => d['status'] == 'cancellation_pending' ? 'Solicitud enviada: el cliente debe aceptar la cancelación en el buzón del SAT.' : 'Factura cancelada');
  }

  Future<void> _email() async {
    final inv = _invoice!;
    final email = await askEmail(context, inv['last_emailed_to']?.toString() ?? asMap(asMap(inv['sale_order'])['client'])['email']?.toString());
    if (email == null) return;
    await _run(() => _api.post('/sale_invoices/${widget.id}/send_email', {'email': email}), (d) => 'Factura enviada a ${d['last_emailed_to'] ?? email}');
  }

  Future<void> _file(String format) async {
    try {
      await openRemoteFile(_api, '/sale_invoices/${widget.id}/download_$format', 'factura_${cfdiFolio(_invoice!)}.$format',
          format == 'pdf' ? 'application/pdf' : 'text/xml');
    } catch (error) {
      if (mounted) showError(context, error);
    }
  }

  Future<void> _payment() async {
    final done = await showModalBottomSheet<bool>(context: context, isScrollControlled: true, useSafeArea: true, builder: (_) => _PaymentSheet(invoice: _invoice!));
    if (done == true) await _load();
  }

  Future<void> _creditNote() async {
    final done = await showModalBottomSheet<bool>(context: context, isScrollControlled: true, useSafeArea: true, builder: (_) => _CreditNoteSheet(invoice: _invoice!));
    if (done == true) await _load();
  }

  @override
  Widget build(BuildContext context) {
    final inv = _invoice;
    final theme = Theme.of(context);
    if (inv == null) {
      return Scaffold(appBar: AppBar(title: const Text('Factura')), body: _error != null ? ErrorView(error: _error!, onRetry: _load) : const LoadingView());
    }
    final status = inv['status']?.toString();
    final order = asMap(inv['sale_order']);
    final client = asMap(order['client']);
    final isPpd = inv['payment_method'] == 'PPD';
    final balance = toNum(inv['balance_due']) ?? 0;
    final creditable = toNum(inv['creditable_amount']) ?? 0;
    final canStamp = status == 'draft' || status == 'error' || status == 'stamping';
    return Scaffold(
      appBar: AppBar(title: Text('Factura ${cfdiFolio(inv)}')),
      body: RefreshIndicator(
        onRefresh: _load,
        child: ListView(padding: const EdgeInsets.all(16), children: [
          const CfdiSandboxBanner(),
          Align(alignment: Alignment.centerLeft, child: cfdiStatusChip(context, status)),
          const SizedBox(height: 8),
          if (status == 'draft') _Note('Esta factura aún no ha sido timbrada ante el SAT. El PDF mientras tanto es un borrador sin validez fiscal.', theme.colorScheme.tertiaryContainer),
          if (status == 'stamping') _Note('La factura se está timbrando. Si no cambia en un par de minutos, reintenta: antes de timbrar se revisa si ya quedó timbrada.', theme.colorScheme.tertiaryContainer),
          if (status == 'error') _Note('El último intento de timbrado falló: ${inv['cfdi_error'] ?? ''}. Al reintentar se revisa primero si ya quedó timbrada.', theme.colorScheme.errorContainer),
          if (status == 'cancellation_pending')
            _Note('La cancelación está en proceso: el cliente debe aceptarla en el buzón tributario del SAT (hasta 72 horas). Usa "Actualizar estatus".', theme.colorScheme.tertiaryContainer),
          SectionCard(title: 'Datos', children: [
            InfoRow('Cliente', client['name']?.toString()),
            InfoRow('RFC', client['tax_id']?.toString()),
            InfoRow('Fecha', formatDate(inv['invoice_date'])),
            InfoRow('Orden de venta', order['order_number']?.toString()),
            InfoRow('Método', paymentMethods[inv['payment_method']] ?? inv['payment_method']?.toString()),
            InfoRow('Forma de pago', invoicePaymentForms[inv['payment_form']] ?? inv['payment_form']?.toString()),
            InfoRow('Uso de CFDI', cfdiUses[inv['cfdi_use']] ?? inv['cfdi_use']?.toString()),
            InfoRow('UUID', inv['cfdi_uuid']?.toString()),
            InfoRow('Enviada a', inv['last_emailed_at'] == null ? null : '${inv['last_emailed_to']} · ${formatDateTime(inv['last_emailed_at'])}'),
          ]),
          const SizedBox(height: 12),
          SectionCard(title: 'Conceptos', children: [
            for (final item in asMapList(order['sale_order_items']))
              ListTile(
                dense: true,
                title: Text(asMap(item['product'])['name']?.toString() ?? item['description']?.toString() ?? ''),
                subtitle: Text('${formatNumber(item['quantity'])} × ${formatMoney(item['unit_price'])}'),
                trailing: Text(formatMoney(item['total_price'])),
              ),
            InfoRow('Subtotal', formatMoney(inv['subtotal'])),
            InfoRow('IVA', formatMoney(inv['iva'])),
            InfoRow('Total', formatMoney(inv['total'])),
          ]),
          if (status == 'stamped' || asMapList(inv['payments']).isNotEmpty || asMapList(inv['credit_notes']).isNotEmpty) ...[
            const SizedBox(height: 12),
            SectionCard(title: 'Saldo de la factura', children: [
              if (isPpd) InfoRow('Pagado (complementos)', formatMoney(inv['amount_paid'])),
              InfoRow('Notas de crédito', formatMoney(inv['amount_credited'])),
              if (isPpd) InfoRow('Saldo pendiente', formatMoney(balance)),
              if (status == 'stamped' && isPpd && balance > 0)
                const Padding(
                  padding: EdgeInsets.fromLTRB(16, 4, 16, 8),
                  child: Text('Por cada pago que recibas de esta factura PPD debes emitir un complemento de pago, a más tardar el día 5 del mes siguiente.'),
                ),
              if (status == 'stamped')
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
                  child: Wrap(spacing: 8, children: [
                    if (isPpd && balance > 0) FilledButton.tonal(onPressed: _busy ? null : _payment, child: const Text('Registrar pago')),
                    if (creditable > 0) OutlinedButton(onPressed: _busy ? null : _creditNote, child: const Text('Emitir nota de crédito')),
                  ]),
                ),
              for (final p in asMapList(inv['payments']))
                ListTile(
                  dense: true,
                  leading: const Icon(Icons.payments_outlined),
                  title: Text('Complemento ${cfdiFolio(p)} · parcialidad ${p['partiality_number']}'),
                  subtitle: Text('${formatDate(p['payment_date'])} · saldo ${formatMoney(p['remaining_balance'])}'),
                  trailing: Text(formatMoney(p['amount'])),
                  onTap: () => context.push('/cfdis/complementos-pago/${p['id']}'),
                ),
              for (final n in asMapList(inv['credit_notes']))
                ListTile(
                  dense: true,
                  leading: const Icon(Icons.undo),
                  title: Text('Nota de crédito ${cfdiFolio(n)}'),
                  subtitle: Text(n['description']?.toString() ?? ''),
                  trailing: Text(formatMoney(n['total'])),
                  onTap: () => context.push('/cfdis/notas-credito/${n['id']}'),
                ),
            ]),
          ],
          const SizedBox(height: 16),
          if (canStamp)
            FilledButton.icon(
              onPressed: _busy ? null : () => _run(() => _api.post('/sale_invoices/${widget.id}/stamp', {}), (_) => 'Factura timbrada'),
              icon: const Icon(Icons.verified_outlined),
              label: Text(_busy ? 'Timbrando…' : status == 'draft' ? 'Timbrar (CFDI)' : 'Reintentar timbrado'),
            ),
          if (status == 'cancellation_pending')
            FilledButton.tonal(
              onPressed: _busy
                  ? null
                  : () => _run(() => _api.post('/sale_invoices/${widget.id}/refresh_status', {}),
                      (d) => d['status'] == 'cancelled' ? 'El SAT confirmó la cancelación' : 'Estatus: ${cfdiStatusLabels[d['status']] ?? d['status']}'),
              child: const Text('Actualizar estatus'),
            ),
          const SizedBox(height: 8),
          OutlinedButton.icon(onPressed: () => _file('pdf'), icon: const Icon(Icons.picture_as_pdf_outlined), label: const Text('Ver o descargar PDF')),
          if (inv['cfdi_uuid'] != null) ...[
            const SizedBox(height: 8),
            OutlinedButton.icon(onPressed: () => _file('xml'), icon: const Icon(Icons.code), label: const Text('Descargar XML')),
            const SizedBox(height: 8),
            OutlinedButton.icon(onPressed: _busy ? null : _email, icon: const Icon(Icons.mail_outline), label: const Text('Enviar por correo')),
          ],
          if (status == 'stamped') ...[
            const SizedBox(height: 8),
            TextButton(style: TextButton.styleFrom(foregroundColor: theme.colorScheme.error), onPressed: _busy ? null : _cancel, child: const Text('Cancelar factura')),
          ],
          const SizedBox(height: 24),
        ]),
      ),
    );
  }
}

class _Note extends StatelessWidget {
  const _Note(this.text, this.color);
  final String text;
  final Color color;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(bottom: 8),
        child: Card(color: color, child: Padding(padding: const EdgeInsets.all(12), child: Text(text))),
      );
}

/// Complemento de pago de una factura PPD. La llave de idempotencia evita
/// emitir dos si se reenvía el formulario.
class _PaymentSheet extends StatefulWidget {
  const _PaymentSheet({required this.invoice});
  final Map<String, dynamic> invoice;

  @override
  State<_PaymentSheet> createState() => _PaymentSheetState();
}

class _PaymentSheetState extends State<_PaymentSheet> {
  final _key = newRequestKey();
  String? _date = isoDate(DateTime.now());
  String _form = '03';
  final _amount = TextEditingController();
  final _operation = TextEditingController();
  bool _busy = false;
  String? _error;

  num get _balance => toNum(widget.invoice['balance_due']) ?? 0;

  Future<void> _submit() async {
    final amount = num.tryParse(_amount.text.trim()) ?? 0;
    if (amount <= 0 || amount > _balance + 0.001) {
      setState(() => _error = 'El monto debe ser mayor a 0 y no exceder el saldo (${formatMoney(_balance)}).');
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final doc = asMap(await context.read<ApiClient>().post('/sale_invoices/${widget.invoice['id']}/payments', {
        'invoice_payment': {'payment_date': _date, 'payment_form': _form, 'amount': amount, if (_operation.text.trim().isNotEmpty) 'operation_number': _operation.text.trim()},
        'idempotency_key': _key,
      }));
      if (!mounted) return;
      showMessage(context,
          doc['status'] == 'stamped' ? 'Complemento de pago ${cfdiFolio(doc)} timbrado' : 'Complemento guardado pero no se pudo timbrar; ábrelo para ver el error y reintentar.');
      Navigator.pop(context, true);
    } catch (error) {
      if (mounted) setState(() => _error = error.toString());
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final count = asMapList(widget.invoice['payments']).where((p) => p['status'] != 'cancelled').length + 1;
    return Padding(
      padding: EdgeInsets.fromLTRB(16, 16, 16, MediaQuery.of(context).viewInsets.bottom + 16),
      child: SingleChildScrollView(
        child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Text('Registrar pago', style: Theme.of(context).textTheme.titleLarge),
          Text('Saldo actual ${formatMoney(_balance)}. Parcialidad número $count.'),
          const SizedBox(height: 12),
          if (_error != null) Text(_error!, style: TextStyle(color: Theme.of(context).colorScheme.error)),
          DateField(label: 'Fecha en que se recibió', value: _date, lastDate: DateTime.now(), onChanged: (v) => setState(() => _date = v)),
          const SizedBox(height: 12),
          DropdownButtonFormField<String>(
            initialValue: _form,
            isExpanded: true,
            decoration: const InputDecoration(labelText: 'Forma de pago'),
            items: [for (final e in satPaymentForms.entries) DropdownMenuItem(value: e.key, child: Text(e.value, overflow: TextOverflow.ellipsis))],
            onChanged: (v) => setState(() => _form = v ?? '03'),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _amount,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            decoration: InputDecoration(
              labelText: 'Monto recibido',
              prefixText: r'$ ',
              suffixIcon: TextButton(onPressed: () => _amount.text = _balance.toStringAsFixed(2), child: const Text('Liquidar')),
            ),
          ),
          const SizedBox(height: 12),
          TextField(controller: _operation, decoration: const InputDecoration(labelText: 'Número de operación (opcional)')),
          const SizedBox(height: 16),
          FilledButton(onPressed: _busy ? null : _submit, child: Text(_busy ? 'Timbrando…' : 'Emitir complemento')),
        ]),
      ),
    );
  }
}

class _CreditNoteSheet extends StatefulWidget {
  const _CreditNoteSheet({required this.invoice});
  final Map<String, dynamic> invoice;

  @override
  State<_CreditNoteSheet> createState() => _CreditNoteSheetState();
}

class _CreditNoteSheetState extends State<_CreditNoteSheet> {
  final _key = newRequestKey();
  String _relation = '01';
  late String _form = widget.invoice['payment_form'] == '99' || widget.invoice['payment_form'] == null ? '01' : widget.invoice['payment_form'].toString();
  final _subtotal = TextEditingController();
  final _description = TextEditingController();
  bool _busy = false;
  String? _error;

  num get _creditable => toNum(widget.invoice['creditable_amount']) ?? 0;
  num get _rate => toNum(widget.invoice['iva_rate']) ?? 0;
  num get _total => ((num.tryParse(_subtotal.text.trim()) ?? 0) * (1 + _rate) * 100).round() / 100;

  Future<void> _submit() async {
    final subtotal = num.tryParse(_subtotal.text.trim()) ?? 0;
    String? message;
    if (_description.text.trim().isEmpty) {
      message = 'Describe el motivo de la nota de crédito.';
    } else if (subtotal <= 0 || _total > _creditable + 0.001) {
      message = 'El total debe ser mayor a 0 y no exceder lo acreditable (${formatMoney(_creditable)}).';
    }
    if (message != null) {
      setState(() => _error = message);
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final doc = asMap(await context.read<ApiClient>().post('/sale_invoices/${widget.invoice['id']}/credit_notes', {
        'credit_note': {'relation_type': _relation, 'description': _description.text.trim(), 'payment_form': _form, 'subtotal': subtotal},
        'idempotency_key': _key,
      }));
      if (!mounted) return;
      showMessage(context, doc['status'] == 'stamped' ? 'Nota de crédito ${cfdiFolio(doc)} timbrada' : 'Nota guardada pero no se pudo timbrar; ábrela para ver el error.');
      Navigator.pop(context, true);
    } catch (error) {
      if (mounted) setState(() => _error = error.toString());
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => Padding(
        padding: EdgeInsets.fromLTRB(16, 16, 16, MediaQuery.of(context).viewInsets.bottom + 16),
        child: SingleChildScrollView(
          child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            Text('Emitir nota de crédito', style: Theme.of(context).textTheme.titleLarge),
            Text('Acreditable: ${formatMoney(_creditable)}'),
            const SizedBox(height: 12),
            if (_error != null) Text(_error!, style: TextStyle(color: Theme.of(context).colorScheme.error)),
            DropdownButtonFormField<String>(
              initialValue: _relation,
              decoration: const InputDecoration(labelText: 'Tipo'),
              items: [for (final e in creditRelations.entries) DropdownMenuItem(value: e.key, child: Text(e.value.$1))],
              onChanged: (v) => setState(() => _relation = v ?? '01'),
            ),
            Text(creditRelations[_relation]!.$2, style: Theme.of(context).textTheme.bodySmall),
            const SizedBox(height: 12),
            DropdownButtonFormField<String>(
              initialValue: satPaymentForms.containsKey(_form) ? _form : '01',
              isExpanded: true,
              decoration: const InputDecoration(labelText: 'Forma de pago'),
              items: [for (final e in satPaymentForms.entries) DropdownMenuItem(value: e.key, child: Text(e.value, overflow: TextOverflow.ellipsis))],
              onChanged: (v) => setState(() => _form = v ?? '01'),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _subtotal,
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              decoration: InputDecoration(labelText: 'Importe sin IVA', prefixText: r'$ ', helperText: 'Total con IVA: ${formatMoney(_total)}'),
              onChanged: (_) => setState(() {}),
            ),
            const SizedBox(height: 12),
            TextField(controller: _description, maxLines: 2, decoration: const InputDecoration(labelText: 'Concepto')),
            const SizedBox(height: 16),
            FilledButton(onPressed: _busy ? null : _submit, child: Text(_busy ? 'Timbrando…' : 'Emitir nota de crédito')),
          ]),
        ),
      );
}
