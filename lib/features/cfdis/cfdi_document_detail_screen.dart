import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../../core/api_client.dart';
import '../../core/files.dart';
import '../../core/formatters.dart';
import '../../core/user_profile.dart';
import '../../widgets/async_states.dart';
import '../../widgets/form_fields.dart';
import 'cfdi_catalogs.dart';

/// Detalle de un complemento de pago, nota de crédito o factura global:
/// timbrar, cancelar, actualizar estatus, enviar por correo y PDF/XML.
class CfdiDocumentDetailScreen extends StatefulWidget {
  const CfdiDocumentDetailScreen({super.key, required this.kind, required this.id});
  final CfdiKind kind;
  final String id;

  @override
  State<CfdiDocumentDetailScreen> createState() => _CfdiDocumentDetailScreenState();
}

class _CfdiDocumentDetailScreenState extends State<CfdiDocumentDetailScreen> {
  Map<String, dynamic>? _doc;
  Object? _error;
  bool _busy = false;

  ApiClient get _api => context.read<ApiClient>();
  String get _base => '/${widget.kind.apiPath}/${widget.id}';

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final data = asMap(await _api.get(_base));
      if (mounted) setState(() => _doc = data);
    } catch (error) {
      if (mounted) setState(() => _error = error);
    }
  }

  Future<void> _act(String action, Map<String, dynamic> data, String Function(Map<String, dynamic>) success) async {
    setState(() => _busy = true);
    try {
      final updated = asMap(await _api.post('$_base/$action', data));
      if (!mounted) return;
      setState(() => _doc = {..._doc!, ...updated});
      showMessage(context, success(updated));
    } catch (error) {
      if (mounted) showError(context, error);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _file(String format) async {
    try {
      await openRemoteFile(_api, '$_base/download_$format', '${widget.kind.singular}_${cfdiFolio(_doc!)}.$format'.replaceAll(' ', '_'),
          format == 'pdf' ? 'application/pdf' : 'text/xml');
    } catch (error) {
      if (mounted) showError(context, error);
    }
  }

  Future<void> _discard() async {
    if (!await confirm(context, title: 'Descartar factura global', message: 'Los tickets volverán a quedar disponibles para facturar.', action: 'Descartar', destructive: true) ||
        !mounted) {
      return;
    }
    try {
      await _api.delete(_base);
      if (mounted) context.pop(true);
    } catch (error) {
      if (mounted) showError(context, error);
    }
  }

  @override
  Widget build(BuildContext context) {
    final doc = _doc;
    final kind = widget.kind;
    final theme = Theme.of(context);
    if (doc == null) {
      return Scaffold(appBar: AppBar(title: Text(kind.singular)), body: _error != null ? ErrorView(error: _error!, onRetry: _load) : const LoadingView());
    }
    final status = doc['status']?.toString();
    final invoice = asMap(doc['sale_invoice']);
    final canStamp = status == 'draft' || status == 'error' || status == 'stamping';
    return Scaffold(
      appBar: AppBar(title: Text('${kind.singular} ${cfdiFolio(doc)}')),
      body: RefreshIndicator(
        onRefresh: _load,
        child: ListView(padding: const EdgeInsets.all(16), children: [
          const CfdiSandboxBanner(),
          Align(alignment: Alignment.centerLeft, child: cfdiStatusChip(context, status)),
          const SizedBox(height: 8),
          if (status == 'error' && doc['cfdi_error'] != null)
            Card(color: theme.colorScheme.errorContainer, child: Padding(padding: const EdgeInsets.all(12), child: Text('No se pudo timbrar: ${doc['cfdi_error']}'))),
          if (status == 'cancellation_pending')
            Card(
              color: theme.colorScheme.tertiaryContainer,
              child: const Padding(padding: EdgeInsets.all(12), child: Text('La cancelación está en proceso: el receptor debe aceptarla en el buzón del SAT.')),
            ),
          SectionCard(title: 'Datos del comprobante', children: [
            if (invoice.isNotEmpty) ...[
              InfoRow('Factura', cfdiFolio(invoice)),
              InfoRow('Cliente', asMap(invoice['client'])['name']?.toString()),
            ],
            if (kind == CfdiKind.payment) ...[
              InfoRow('Fecha de pago', formatDate(doc['payment_date'])),
              InfoRow('Forma de pago', satPaymentForms[doc['payment_form']] ?? doc['payment_form']?.toString()),
              InfoRow('Monto', formatMoney(doc['amount'])),
              InfoRow('Parcialidad', doc['partiality_number']?.toString()),
              InfoRow('Saldo anterior', formatMoney(doc['previous_balance'])),
              InfoRow('Saldo insoluto', formatMoney(doc['remaining_balance'])),
              InfoRow('Operación', doc['operation_number']?.toString()),
            ],
            if (kind == CfdiKind.creditNote) ...[
              InfoRow('Tipo', doc['relation_label']?.toString()),
              InfoRow('Concepto', doc['description']?.toString()),
              InfoRow('Forma de pago', satPaymentForms[doc['payment_form']] ?? doc['payment_form']?.toString()),
              InfoRow('Subtotal', formatMoney(doc['subtotal'])),
              InfoRow('IVA', formatMoney(doc['iva'])),
              InfoRow('Total', formatMoney(doc['total'])),
            ],
            if (kind == CfdiKind.globalInvoice) ...[
              InfoRow('Periodicidad', '${doc['periodicity_label'] ?? ''} (meses ${doc['months']}/${doc['year']})'),
              InfoRow('Periodo', '${formatDate(doc['period_start'])} – ${formatDate(doc['period_end'])}'),
              InfoRow('Forma de pago', satPaymentForms[doc['payment_form']] ?? doc['payment_form']?.toString()),
              InfoRow('Subtotal', formatMoney(doc['subtotal'])),
              InfoRow('IVA', formatMoney(doc['iva'])),
              InfoRow('Total', formatMoney(doc['total'])),
            ],
            InfoRow('UUID', doc['cfdi_uuid']?.toString()),
            InfoRow('Timbrado', doc['stamped_at'] == null ? null : formatDateTime(doc['stamped_at'])),
            InfoRow('Cancelado', doc['cancelled_at'] == null ? null : '${formatDateTime(doc['cancelled_at'])} (motivo ${doc['cancellation_motive']})'),
            InfoRow('Enviado a', doc['last_emailed_at'] == null ? null : '${doc['last_emailed_to']} · ${formatDateTime(doc['last_emailed_at'])}'),
          ]),
          if (kind == CfdiKind.globalInvoice && asMapList(doc['tickets']).isNotEmpty) ...[
            const SizedBox(height: 12),
            SectionCard(title: 'Tickets incluidos (${doc['tickets_count']})', children: [
              for (final t in asMapList(doc['tickets']))
                ListTile(dense: true, title: Text(t['folio']?.toString() ?? ''), subtitle: Text(formatDate(t['date'])), trailing: Text(formatMoney(t['total']))),
            ]),
          ],
          const SizedBox(height: 16),
          if (canStamp)
            FilledButton.icon(
              onPressed: _busy ? null : () => _act('stamp', {}, (_) => 'Comprobante timbrado'),
              icon: const Icon(Icons.verified_outlined),
              label: Text(_busy ? 'Timbrando…' : status == 'draft' ? 'Timbrar' : 'Reintentar timbrado'),
            ),
          if (status == 'cancellation_pending')
            FilledButton.tonal(
              onPressed: _busy
                  ? null
                  : () => _act('refresh_status', {}, (d) => d['status'] == 'cancelled' ? 'El SAT confirmó la cancelación' : 'Estatus: ${cfdiStatusLabels[d['status']] ?? d['status']}'),
              child: const Text('Actualizar estatus'),
            ),
          const SizedBox(height: 8),
          OutlinedButton.icon(onPressed: () => _file('pdf'), icon: const Icon(Icons.picture_as_pdf_outlined), label: const Text('Ver o descargar PDF')),
          if (doc['cfdi_uuid'] != null) ...[
            const SizedBox(height: 8),
            OutlinedButton.icon(onPressed: () => _file('xml'), icon: const Icon(Icons.code), label: const Text('Descargar XML')),
            const SizedBox(height: 8),
            OutlinedButton.icon(
              onPressed: _busy
                  ? null
                  : () async {
                      final email = await askEmail(context, doc['last_emailed_to']?.toString() ?? asMap(invoice['client'])['email']?.toString());
                      if (email != null) await _act('send_email', {'email': email}, (d) => 'Enviado a ${d['last_emailed_to'] ?? email}');
                    },
              icon: const Icon(Icons.mail_outline),
              label: const Text('Enviar por correo'),
            ),
          ],
          if (status == 'stamped') ...[
            const SizedBox(height: 8),
            TextButton(
              style: TextButton.styleFrom(foregroundColor: theme.colorScheme.error),
              onPressed: _busy
                  ? null
                  : () async {
                      final result = await askCancellation(context);
                      if (result != null) {
                        await _act('cancel', {'motive': result.$1, 'uuid_replacement': result.$2},
                            (d) => d['status'] == 'cancellation_pending' ? 'Solicitud enviada: el receptor debe aceptarla en el buzón del SAT.' : 'Comprobante cancelado');
                      }
                    },
              child: const Text('Cancelar comprobante'),
            ),
          ],
          if (kind == CfdiKind.globalInvoice && (status == 'draft' || status == 'error')) ...[
            const SizedBox(height: 8),
            TextButton(style: TextButton.styleFrom(foregroundColor: theme.colorScheme.error), onPressed: _busy ? null : _discard, child: const Text('Descartar factura global')),
          ],
          const SizedBox(height: 24),
        ]),
      ),
    );
  }
}
