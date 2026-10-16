import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../../core/api_client.dart';
import '../../core/files.dart';
import '../../core/formatters.dart';
import '../../core/user_profile.dart';
import '../../widgets/async_states.dart';
import '../../widgets/form_fields.dart';
import '../../widgets/order_lines.dart';
import '../../widgets/status.dart';
import 'purchase_order_form_screen.dart';
import 'receive_sheet.dart';

class PurchaseOrderDetailScreen extends StatefulWidget {
  const PurchaseOrderDetailScreen({super.key, required this.id});
  final String id;

  @override
  State<PurchaseOrderDetailScreen> createState() => _PurchaseOrderDetailScreenState();
}

class _PurchaseOrderDetailScreenState extends State<PurchaseOrderDetailScreen> {
  late Future<Map<String, dynamic>> _future = _load();
  bool _changed = false;

  Future<Map<String, dynamic>> _load() async => asMap(await context.read<ApiClient>().get('/purchase_orders/${widget.id}'));

  void _reload() {
    _changed = true;
    setState(() => _future = _load());
  }

  Future<void> _post(Map<String, dynamic> order, String action, String title, String message, {bool destructive = false}) async {
    if (!await confirm(context, title: title, message: message, action: title, destructive: destructive) || !mounted) return;
    try {
      final api = context.read<ApiClient>();
      if (action == 'delete') {
        await api.delete('/purchase_orders/${order['id']}');
        if (mounted) context.pop(true);
        return;
      }
      await api.post('/purchase_orders/${order['id']}/$action', {});
      _reload();
    } catch (error) {
      if (mounted) showError(context, error);
    }
  }

  Future<void> _edit(Map<String, dynamic> order) async {
    final saved = await Navigator.of(context).push<bool>(MaterialPageRoute(builder: (_) => PurchaseOrderFormScreen(order: order)));
    if (saved == true) _reload();
  }

  Future<void> _receive(Map<String, dynamic> order) async {
    final done = await showReceiveSheet(context, order);
    if (done == true && mounted) {
      showMessage(context, 'Productos recibidos');
      _reload();
    }
  }

  Future<void> _pdf(Map<String, dynamic> order) async {
    try {
      await openRemotePdf(context.read<ApiClient>(), '/purchase_orders/${order['id']}/download_purchase_order', 'compra-${order['order_number'] ?? order['id']}.pdf');
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
        appBar: AppBar(title: const Text('Orden de compra')),
        body: FutureBuilder<Map<String, dynamic>>(
          future: _future,
          builder: (context, snapshot) {
            if (snapshot.connectionState != ConnectionState.done) return const LoadingView();
            if (snapshot.hasError) return ErrorView(error: snapshot.error!, onRetry: () => setState(() => _future = _load()));
            final o = snapshot.data!;
            final status = o['status']?.toString();
            final items = asMapList(o['purchase_order_items']);
            final invoices = asMapList(o['invoices']);
            return RefreshIndicator(
              onRefresh: () async => _reload(),
              child: ListView(padding: const EdgeInsets.all(16), children: [
                Row(children: [
                  Expanded(child: Text('Compra ${o['order_number'] ?? '#${o['id']}'}', style: theme.textTheme.headlineSmall)),
                  purchaseStatus.chip(context, status),
                ]),
                const SizedBox(height: 12),
                SectionCard(title: 'Datos', children: [
                  InfoRow('Proveedor', asMap(o['supplier'])['name']?.toString()),
                  InfoRow('Fecha', formatDate(o['order_date'])),
                  InfoRow('Entrega', formatDate(o['expected_delivery_date'])),
                  InfoRow('Lugar de entrega', o['delivery_place']?.toString()),
                  InfoRow('Atención', o['attention']?.toString()),
                  InfoRow('Moneda', o['currency']?.toString()),
                ]),
                const SizedBox(height: 12),
                DocumentLines(
                  items: items,
                  trailing: (item) => '${formatNumber(item['received_quantity'] ?? 0)} / ${formatNumber(item['quantity'])} recibido',
                ),
                const SizedBox(height: 12),
                SectionCard(title: 'Importes', children: [
                  InfoRow('Subtotal', formatMoney(o['subtotal'])),
                  InfoRow('IVA', formatMoney(o['iva'])),
                  InfoRow('Total', '${formatMoney(o['total'])} ${o['currency'] ?? ''}'),
                ]),
                if (invoices.isNotEmpty) ...[
                  const SizedBox(height: 12),
                  SectionCard(title: 'Recepciones', children: [
                    for (final inv in invoices)
                      ListTile(
                        dense: true,
                        leading: const Icon(Icons.receipt_outlined),
                        title: Text('Factura ${inv['invoice_number'] ?? ''}'),
                        subtitle: Text('${formatDate(inv['invoice_date'])}${inv['received_by'] != null ? ' · ${inv['received_by']}' : ''}'),
                        trailing: Text(formatMoney(inv['total'])),
                      ),
                  ]),
                ],
                const SizedBox(height: 16),
                if (status == 'approved' || status == 'partially_received')
                  Padding(
                    padding: const EdgeInsets.only(bottom: 8),
                    child: FilledButton.icon(onPressed: () => _receive(o), icon: const Icon(Icons.move_to_inbox_outlined), label: const Text('Recibir mercancía')),
                  ),
                if (status == 'draft' || status == 'pending')
                  Padding(
                    padding: const EdgeInsets.only(bottom: 8),
                    child: FilledButton.icon(
                      onPressed: () => _post(o, 'approve', 'Aprobar', 'La orden quedará lista para recibir mercancía.'),
                      icon: const Icon(Icons.check),
                      label: const Text('Aprobar'),
                    ),
                  ),
                if (status == 'draft' || status == 'approved')
                  Padding(
                    padding: const EdgeInsets.only(bottom: 8),
                    child: OutlinedButton.icon(onPressed: () => _edit(o), icon: const Icon(Icons.edit_outlined), label: const Text('Editar orden')),
                  ),
                OutlinedButton.icon(onPressed: () => _pdf(o), icon: const Icon(Icons.picture_as_pdf_outlined), label: const Text('Descargar PDF')),
                if (status == 'draft' || status == 'pending' || status == 'approved') ...[
                  const SizedBox(height: 8),
                  OutlinedButton(
                    style: OutlinedButton.styleFrom(foregroundColor: theme.colorScheme.error),
                    onPressed: () => _post(o, 'cancel', 'Cancelar orden', '¿Cancelar esta orden de compra?', destructive: true),
                    child: const Text('Cancelar orden'),
                  ),
                ],
                if (status == 'draft' || status == 'cancelled') ...[
                  const SizedBox(height: 8),
                  TextButton(
                    style: TextButton.styleFrom(foregroundColor: theme.colorScheme.error),
                    onPressed: () => _post(o, 'delete', 'Eliminar', '¿Eliminar esta orden de compra?', destructive: true),
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
