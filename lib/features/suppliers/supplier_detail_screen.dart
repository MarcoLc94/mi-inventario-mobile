import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../../core/api_client.dart';
import '../../core/formatters.dart';
import '../../core/session.dart';
import '../../core/user_profile.dart';
import '../../widgets/async_states.dart';
import '../../widgets/form_fields.dart';
import '../../widgets/status.dart';
import 'supplier_form_screen.dart';

class SupplierDetailScreen extends StatefulWidget {
  const SupplierDetailScreen({super.key, required this.id});
  final String id;

  @override
  State<SupplierDetailScreen> createState() => _SupplierDetailScreenState();
}

class _SupplierDetailScreenState extends State<SupplierDetailScreen> {
  late Future<Map<String, dynamic>> _future = _load();
  Future<List<Map<String, dynamic>>>? _history;
  bool _changed = false;

  Future<Map<String, dynamic>> _load() async {
    final api = context.read<ApiClient>();
    // Sin Facturación el proveedor es solo catálogo: no hay compras ni historial.
    if (context.read<SessionController>().profile?.invoicingActive ?? false) {
      _history = api.get('/suppliers/${widget.id}/purchase_history').then(asMapList);
    }
    return asMap(await api.get('/suppliers/${widget.id}'));
  }

  Future<void> _edit(Map<String, dynamic> supplier) async {
    final saved = await Navigator.of(context).push<Map<String, dynamic>>(MaterialPageRoute(builder: (_) => SupplierFormScreen(supplier: supplier)));
    if (saved != null && mounted) {
      _changed = true;
      setState(() => _future = _load());
    }
  }

  Future<void> _delete(Map<String, dynamic> supplier) async {
    if (!await confirm(context, title: 'Eliminar proveedor', message: '¿Eliminar "${supplier['name']}"?', action: 'Eliminar', destructive: true) || !mounted) return;
    try {
      await context.read<ApiClient>().delete('/suppliers/${supplier['id']}');
      if (mounted) context.pop(true);
    } catch (error) {
      if (mounted) showError(context, error);
    }
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) Navigator.of(context).pop(_changed);
      },
      child: FutureBuilder<Map<String, dynamic>>(
        future: _future,
        builder: (context, snapshot) {
          final s = snapshot.data;
          return Scaffold(
            appBar: AppBar(
              title: const Text('Proveedor'),
              actions: [
                if (s != null) IconButton(tooltip: 'Editar', onPressed: () => _edit(s), icon: const Icon(Icons.edit_outlined)),
                if (s != null)
                  PopupMenuButton<String>(
                    onSelected: (_) => _delete(s),
                    itemBuilder: (_) => const [PopupMenuItem(value: 'delete', child: Text('Eliminar proveedor'))],
                  ),
              ],
            ),
            body: snapshot.connectionState != ConnectionState.done
                ? const LoadingView()
                : snapshot.hasError
                    ? ErrorView(error: snapshot.error!, onRetry: () => setState(() => _future = _load()))
                    : ListView(padding: const EdgeInsets.all(16), children: [
                        Row(children: [
                          Expanded(child: Text(s!['name']?.toString() ?? '', style: Theme.of(context).textTheme.headlineSmall)),
                          partnerStatus.chip(context, s['status']),
                        ]),
                        const SizedBox(height: 12),
                        SectionCard(title: 'Datos', children: [
                          InfoRow('Razón social', s['contact_name']?.toString()),
                          InfoRow('RFC', s['tax_id']?.toString()),
                          InfoRow('Correo', s['email']?.toString()),
                          InfoRow('Teléfono', s['phone']?.toString()),
                          InfoRow('Dirección', [s['address'], s['city'], s['state'], s['postal_code'], s['country']].where((v) => v != null && v.toString().isNotEmpty).join(', ')),
                        ]),
                        const SizedBox(height: 12),
                        SectionCard(title: 'Condiciones de compra', children: [
                          InfoRow('Moneda', s['currency']?.toString()),
                          InfoRow('Entrega', s['lead_time_days'] == null ? null : '${s['lead_time_days']} días'),
                          InfoRow('Compra mínima', s['minimum_order_quantity'] == null ? null : formatNumber(s['minimum_order_quantity'])),
                          InfoRow('Límite de crédito', formatMoney(s['credit_limit'])),
                          InfoRow('Notas', s['notes']?.toString()),
                        ]),
                        if (_history != null) ...[
                          const SizedBox(height: 12),
                          FutureBuilder<List<Map<String, dynamic>>>(
                            future: _history,
                            builder: (context, h) => SectionCard(title: 'Compras y devoluciones', children: [
                              if (h.connectionState != ConnectionState.done) const Padding(padding: EdgeInsets.all(16), child: LinearProgressIndicator()),
                              if (h.hasData && h.data!.isEmpty) const Padding(padding: EdgeInsets.fromLTRB(16, 0, 16, 8), child: Text('Sin movimientos.')),
                              for (final item in h.data ?? const <Map<String, dynamic>>[])
                                ListTile(
                                  dense: true,
                                  leading: Icon(item['type'] == 'return' ? Icons.keyboard_return : Icons.shopping_cart_outlined),
                                  title: Text('${item['type'] == 'return' ? 'Devolución' : 'Compra'} ${item['number'] ?? ''}'),
                                  subtitle: Text('${formatDate(item['date'])} · ${(item['type'] == 'return' ? returnStatus : purchaseStatus).label(item['status'])}'),
                                  trailing: Text(formatMoney(item['amount'])),
                                  onTap: () => context.push('${item['type'] == 'return' ? '/suppliers/returns' : '/suppliers/orders'}/${item['id']}'),
                                ),
                            ]),
                          ),
                        ],
                        const SizedBox(height: 24),
                      ]),
          );
        },
      ),
    );
  }
}
