import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../../core/api_client.dart';
import '../../core/files.dart';
import '../../core/formatters.dart';
import '../../core/session.dart';
import '../../core/user_profile.dart';
import '../../widgets/async_states.dart';
import '../../widgets/form_fields.dart';
import '../../widgets/order_lines.dart';
import '../../widgets/status.dart';
import '../cfdis/cfdi_catalogs.dart';
import 'sale_order_form_screen.dart';

class SaleOrderDetailScreen extends StatefulWidget {
  const SaleOrderDetailScreen({super.key, required this.id});
  final String id;

  @override
  State<SaleOrderDetailScreen> createState() => _SaleOrderDetailScreenState();
}

class _SaleOrderDetailScreenState extends State<SaleOrderDetailScreen> {
  late Future<Map<String, dynamic>> _future = _load();
  bool _changed = false;

  Future<Map<String, dynamic>> _load() async => asMap(await context.read<ApiClient>().get('/sale_orders/${widget.id}'));

  void _reload() {
    _changed = true;
    setState(() => _future = _load());
  }

  Future<void> _action(String action, String title, String message, {bool destructive = false}) async {
    if (!await confirm(context, title: title, message: message, action: title, destructive: destructive) || !mounted) return;
    try {
      final api = context.read<ApiClient>();
      if (action == 'delete') {
        await api.delete('/sale_orders/${widget.id}');
        if (mounted) context.pop(true);
        return;
      }
      await api.post('/sale_orders/${widget.id}/$action', {});
      _reload();
    } catch (error) {
      if (mounted) showError(context, error);
    }
  }

  Future<void> _edit(Map<String, dynamic> order) async {
    final saved = await Navigator.of(context).push<bool>(MaterialPageRoute(builder: (_) => SaleOrderFormScreen(order: order)));
    if (saved == true) _reload();
  }

  Future<void> _invoice(Map<String, dynamic> order) async {
    final invoice = await showModalBottomSheet<Map<String, dynamic>>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (_) => _CreateInvoiceSheet(order: order),
    );
    if (invoice != null && mounted) {
      _changed = true;
      await context.push('/cfdis/facturas/${invoice['id']}');
      if (mounted) setState(() => _future = _load());
    }
  }

  Future<void> _pdf(Map<String, dynamic> order, String path, String name) async {
    try {
      await openRemotePdf(context.read<ApiClient>(), '/sale_orders/${widget.id}/$path', '$name-${order['order_number'] ?? widget.id}.pdf');
    } catch (error) {
      if (mounted) showError(context, error);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) Navigator.of(context).pop(_changed);
      },
      child: Scaffold(
        appBar: AppBar(title: const Text('Orden de venta')),
        body: FutureBuilder<Map<String, dynamic>>(
          future: _future,
          builder: (context, snapshot) {
            if (snapshot.connectionState != ConnectionState.done) return const LoadingView();
            if (snapshot.hasError) return ErrorView(error: snapshot.error!, onRetry: () => setState(() => _future = _load()));
            final o = snapshot.data!;
            final status = o['status']?.toString();
            final subtotal = toNum(o['calculated_subtotal'] ?? o['subtotal']) ?? 0;
            final total = toNum(o['calculated_total'] ?? o['total_amount']) ?? 0;
            return RefreshIndicator(
              onRefresh: () async => _reload(),
              child: ListView(padding: const EdgeInsets.all(16), children: [
                Row(children: [
                  Expanded(child: Text('Venta ${o['order_number'] ?? '#${o['id']}'}', style: theme.textTheme.headlineSmall)),
                  saleStatus.chip(context, status),
                ]),
                const SizedBox(height: 12),
                SectionCard(title: 'Datos', children: [
                  InfoRow('Cliente', asMap(o['client'])['name']?.toString() ?? 'Público en general'),
                  InfoRow('Fecha', formatDate(o['order_date'])),
                  InfoRow('Entrega', formatDate(o['expected_delivery_date'])),
                  InfoRow('Vendedor', '${asMap(o['user'])['first_name'] ?? ''} ${asMap(o['user'])['last_name'] ?? ''}'.trim()),
                  InfoRow('Origen', o['source'] == 'pos' ? 'Punto de venta' : null),
                  InfoRow('Observaciones', o['notes']?.toString()),
                ]),
                const SizedBox(height: 12),
                DocumentLines(items: asMapList(o['sale_order_items'])),
                const SizedBox(height: 12),
                SectionCard(title: 'Importes', children: [
                  InfoRow('Subtotal', formatMoney(subtotal)),
                  InfoRow('IVA', formatMoney(total - subtotal)),
                  InfoRow('Total', formatMoney(total)),
                ]),
                const SizedBox(height: 16),
                if (status == 'draft')
                  Padding(
                    padding: const EdgeInsets.only(bottom: 8),
                    child: FilledButton.icon(
                      onPressed: () => _action('approve', 'Aprobar', 'Se apartarán las existencias de los productos.'),
                      icon: const Icon(Icons.check),
                      label: const Text('Aprobar'),
                    ),
                  ),
                if (status == 'approved')
                  Padding(
                    padding: const EdgeInsets.only(bottom: 8),
                    child: FilledButton.icon(
                      onPressed: () => _action('ship', 'Marcar como enviada', 'La orden se marcará como entregada al cliente.'),
                      icon: const Icon(Icons.local_shipping_outlined),
                      label: const Text('Marcar como enviada'),
                    ),
                  ),
                if ((status == 'shipped' || status == 'completed') && (context.read<SessionController>().profile?.canReadSaleInvoices ?? false))
                  Padding(
                    padding: const EdgeInsets.only(bottom: 8),
                    child: o['sale_invoice'] != null && asMap(o['sale_invoice'])['status'] != 'cancelled'
                        ? FilledButton.tonalIcon(
                            onPressed: () => context.push('/cfdis/facturas/${asMap(o['sale_invoice'])['id']}'),
                            icon: const Icon(Icons.description_outlined),
                            label: Text('Ver factura ${cfdiFolio(asMap(o['sale_invoice']))}'),
                          )
                        : FilledButton.icon(onPressed: () => _invoice(o), icon: const Icon(Icons.description_outlined), label: const Text('Facturar')),
                  ),
                if (status == 'draft')
                  Padding(
                    padding: const EdgeInsets.only(bottom: 8),
                    child: OutlinedButton.icon(onPressed: () => _edit(o), icon: const Icon(Icons.edit_outlined), label: const Text('Editar orden')),
                  ),
                OutlinedButton.icon(
                  onPressed: () => _pdf(o, 'download_sale_order', 'venta'),
                  icon: const Icon(Icons.picture_as_pdf_outlined),
                  label: const Text('Descargar orden (PDF)'),
                ),
                if (status == 'shipped' || status == 'completed') ...[
                  const SizedBox(height: 8),
                  OutlinedButton.icon(
                    onPressed: () => _pdf(o, 'download_remission', 'remision'),
                    icon: const Icon(Icons.receipt_outlined),
                    label: const Text('Descargar remisión'),
                  ),
                ],
                if (status == 'approved') ...[
                  const SizedBox(height: 8),
                  OutlinedButton(
                    style: OutlinedButton.styleFrom(foregroundColor: theme.colorScheme.error),
                    onPressed: () => _action('cancel', 'Cancelar orden', 'Se cancelará la orden y se restaurarán las existencias descontadas.', destructive: true),
                    child: const Text('Cancelar orden'),
                  ),
                ],
                if (status == 'draft' || status == 'pending' || status == 'cancelled') ...[
                  const SizedBox(height: 8),
                  TextButton(
                    style: TextButton.styleFrom(foregroundColor: theme.colorScheme.error),
                    onPressed: () => _action('delete', 'Eliminar', '¿Eliminar esta orden de venta?', destructive: true),
                    child: const Text('Eliminar'),
                  ),
                ],
                const SizedBox(height: 24),
              ]),
            );
          },
        ),
      ),
    );
  }
}

/// Datos de la factura (CFDI) de una orden de venta enviada.
class _CreateInvoiceSheet extends StatefulWidget {
  const _CreateInvoiceSheet({required this.order});
  final Map<String, dynamic> order;

  @override
  State<_CreateInvoiceSheet> createState() => _CreateInvoiceSheetState();
}

class _CreateInvoiceSheetState extends State<_CreateInvoiceSheet> {
  String _method = 'PUE';
  String _form = '03';
  late String _use = cfdiUses.containsKey(asMap(widget.order['client'])['cfdi_use']) ? asMap(widget.order['client'])['cfdi_use'].toString() : 'G03';
  bool _busy = false;
  String? _error;

  Future<void> _create() async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final invoice = asMap(await context.read<ApiClient>().post('/sale_orders/${widget.order['id']}/sale_invoices', {
        'sale_invoice': {'payment_method': _method, 'payment_form': _method == 'PPD' ? '99' : _form, 'cfdi_use': _use},
      }));
      if (mounted) Navigator.pop(context, invoice);
    } catch (error) {
      if (mounted) setState(() => _error = error.toString());
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => Padding(
        padding: EdgeInsets.fromLTRB(16, 16, 16, MediaQuery.of(context).viewInsets.bottom + 16),
        child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Text('Datos de la factura', style: Theme.of(context).textTheme.titleLarge),
          const SizedBox(height: 12),
          if (_error != null) Text(_error!, style: TextStyle(color: Theme.of(context).colorScheme.error)),
          DropdownButtonFormField<String>(
            initialValue: _method,
            isExpanded: true,
            decoration: const InputDecoration(labelText: 'Método de pago'),
            items: [for (final e in paymentMethods.entries) DropdownMenuItem(value: e.key, child: Text(e.value, overflow: TextOverflow.ellipsis))],
            onChanged: (v) => setState(() => _method = v ?? 'PUE'),
          ),
          const SizedBox(height: 12),
          DropdownButtonFormField<String>(
            initialValue: _method == 'PPD' ? '99' : _form,
            isExpanded: true,
            decoration: const InputDecoration(labelText: 'Forma de pago'),
            items: [
              for (final e in invoicePaymentForms.entries)
                if (_method == 'PPD' || e.key != '99') DropdownMenuItem(value: e.key, child: Text(e.value, overflow: TextOverflow.ellipsis)),
            ],
            onChanged: _method == 'PPD' ? null : (v) => setState(() => _form = v ?? '03'),
          ),
          const SizedBox(height: 12),
          DropdownButtonFormField<String>(
            initialValue: _use,
            isExpanded: true,
            decoration: const InputDecoration(labelText: 'Uso de CFDI'),
            items: [for (final e in cfdiUses.entries) DropdownMenuItem(value: e.key, child: Text(e.value, overflow: TextOverflow.ellipsis))],
            onChanged: (v) => setState(() => _use = v ?? 'G03'),
          ),
          const SizedBox(height: 8),
          Text(
            _method == 'PPD'
                ? 'PPD: el cliente pagará después o en parcialidades. La forma de pago queda en 99 y cada pago se registra con un complemento de pago.'
                : 'PUE: el cliente ya pagó completo. Indica cómo pagó.',
            style: Theme.of(context).textTheme.bodySmall,
          ),
          const SizedBox(height: 16),
          FilledButton(onPressed: _busy ? null : _create, child: Text(_busy ? 'Creando…' : 'Crear factura')),
        ]),
      );
}
