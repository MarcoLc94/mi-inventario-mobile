import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../../core/api_client.dart';
import '../../core/files.dart';
import '../../core/formatters.dart';
import '../../core/user_profile.dart';
import '../../widgets/async_states.dart';
import '../../widgets/form_fields.dart';
import '../../widgets/status.dart';
import 'return_kind.dart';

class ReturnDetailScreen extends StatefulWidget {
  const ReturnDetailScreen({super.key, required this.kind, required this.id});
  final ReturnKind kind;
  final String id;

  @override
  State<ReturnDetailScreen> createState() => _ReturnDetailScreenState();
}

class _ReturnDetailScreenState extends State<ReturnDetailScreen> {
  late Future<Map<String, dynamic>> _future = _load();
  bool _changed = false;

  Future<Map<String, dynamic>> _load() async => asMap(await context.read<ApiClient>().get('${widget.kind.endpoint}/${widget.id}'));

  Future<void> _action(String action, String title, String message, {bool destructive = false}) async {
    if (!await confirm(context, title: title, message: message, action: title, destructive: destructive) || !mounted) return;
    try {
      final api = context.read<ApiClient>();
      if (action == 'delete') {
        await api.delete('${widget.kind.endpoint}/${widget.id}');
        if (mounted) context.pop(true);
        return;
      }
      await api.post('${widget.kind.endpoint}/${widget.id}/$action', {});
      _changed = true;
      setState(() => _future = _load());
    } catch (error) {
      if (mounted) showError(context, error);
    }
  }

  Future<void> _pdf(Map<String, dynamic> ret) async {
    try {
      await openRemotePdf(context.read<ApiClient>(), '${widget.kind.endpoint}/${widget.id}/${widget.kind.pdfPath}', '${ret['return_number'] ?? 'devolucion-${widget.id}'}.pdf');
    } catch (error) {
      if (mounted) showError(context, error);
    }
  }

  @override
  Widget build(BuildContext context) {
    final kind = widget.kind;
    final theme = Theme.of(context);
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) Navigator.of(context).pop(_changed);
      },
      child: Scaffold(
        appBar: AppBar(title: const Text('Devolución')),
        body: FutureBuilder<Map<String, dynamic>>(
          future: _future,
          builder: (context, snapshot) {
            if (snapshot.connectionState != ConnectionState.done) return const LoadingView();
            if (snapshot.hasError) return ErrorView(error: snapshot.error!, onRetry: () => setState(() => _future = _load()));
            final r = snapshot.data!;
            final status = r['status']?.toString();
            return ListView(padding: const EdgeInsets.all(16), children: [
              Row(children: [
                Expanded(child: Text(r['return_number']?.toString() ?? 'Devolución #${r['id']}', style: theme.textTheme.headlineSmall)),
                returnStatus.chip(context, status),
              ]),
              const SizedBox(height: 12),
              SectionCard(title: 'Datos', children: [
                InfoRow(kind.partnerLabel, kind.partnerName(r)),
                InfoRow(kind.documentLabel, kind.document(r)['order_number']?.toString()),
                InfoRow('Fecha', formatDate(r['return_date'])),
                InfoRow('Motivo', kind.reasons[r['reason']] ?? r['reason']?.toString()),
                InfoRow(kind.isSupplier ? 'Crédito' : 'Reembolso', formatMoney(r[kind.totalKey])),
                InfoRow('Notas', r['notes']?.toString()),
              ]),
              const SizedBox(height: 12),
              SectionCard(title: 'Productos', children: [
                for (final item in asMapList(r[kind.itemsKey]))
                  ListTile(
                    dense: true,
                    title: Text(asMap(item['product'])['name']?.toString() ?? 'Producto #${item['product_id']}'),
                    subtitle: Text([
                      kind.conditions[item['condition']] ?? item['condition']?.toString() ?? '',
                      if ((item['reason']?.toString() ?? '').isNotEmpty) kind.reasons[item['reason']] ?? item['reason'],
                      if (item['lot_number'] != null) 'Lote ${item['lot_number']}',
                    ].where((t) => t.toString().isNotEmpty).join(' · ')),
                    trailing: Text('${formatNumber(item['quantity'])} ${asMap(item['product'])['base_unit'] ?? ''}'),
                  ),
              ]),
              const SizedBox(height: 16),
              if (status == 'pending') ...[
                FilledButton.icon(
                  onPressed: () => _action('approve', 'Aprobar', 'La devolución quedará lista para procesarse.'),
                  icon: const Icon(Icons.check),
                  label: const Text('Aprobar'),
                ),
                const SizedBox(height: 8),
                OutlinedButton(
                  onPressed: () => _action('reject', 'Rechazar', '¿Rechazar esta devolución?', destructive: true),
                  child: const Text('Rechazar'),
                ),
                const SizedBox(height: 8),
              ],
              if (status == 'approved') ...[
                FilledButton.icon(
                  onPressed: () => _action('process_return', 'Procesar',
                      kind.isSupplier ? 'Se descontarán las existencias devueltas al proveedor.' : 'Se reintegrarán al inventario los productos en buen estado.'),
                  icon: const Icon(Icons.inventory_outlined),
                  label: const Text('Procesar devolución'),
                ),
                const SizedBox(height: 8),
              ],
              OutlinedButton.icon(onPressed: () => _pdf(r), icon: const Icon(Icons.picture_as_pdf_outlined), label: const Text('Descargar PDF')),
              if (status == 'pending' || status == 'rejected') ...[
                const SizedBox(height: 8),
                TextButton(
                  style: TextButton.styleFrom(foregroundColor: theme.colorScheme.error),
                  onPressed: () => _action('delete', 'Eliminar', '¿Eliminar esta devolución?', destructive: true),
                  child: const Text('Eliminar'),
                ),
              ],
              const SizedBox(height: 24),
            ]);
          },
        ),
      ),
    );
  }
}
