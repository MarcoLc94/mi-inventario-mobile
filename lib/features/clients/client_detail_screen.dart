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
import '../cfdis/cfdi_catalogs.dart';
import 'client_form_screen.dart';

class ClientDetailScreen extends StatefulWidget {
  const ClientDetailScreen({super.key, required this.id});
  final String id;

  @override
  State<ClientDetailScreen> createState() => _ClientDetailScreenState();
}

class _ClientDetailScreenState extends State<ClientDetailScreen> {
  late Future<Map<String, dynamic>> _future = _load();
  Future<List<Map<String, dynamic>>>? _history;
  bool _changed = false;

  Future<Map<String, dynamic>> _load() async {
    final api = context.read<ApiClient>();
    if (context.read<SessionController>().profile?.invoicingActive ?? false) {
      _history = api.get('/clients/${widget.id}/sales_history').then(asMapList);
    }
    return asMap(await api.get('/clients/${widget.id}'));
  }

  Future<void> _edit(Map<String, dynamic> client) async {
    final saved = await Navigator.of(context).push<Map<String, dynamic>>(MaterialPageRoute(builder: (_) => ClientFormScreen(client: client)));
    if (saved != null && mounted) {
      _changed = true;
      setState(() => _future = _load());
    }
  }

  Future<void> _delete(Map<String, dynamic> client) async {
    if (!await confirm(context, title: 'Eliminar cliente', message: '¿Eliminar "${client['name']}"?', action: 'Eliminar', destructive: true) || !mounted) return;
    try {
      await context.read<ApiClient>().delete('/clients/${client['id']}');
      if (mounted) context.pop(true);
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
      child: FutureBuilder<Map<String, dynamic>>(
        future: _future,
        builder: (context, snapshot) {
          final c = snapshot.data;
          return Scaffold(
            appBar: AppBar(
              title: const Text('Cliente'),
              actions: [
                if (c != null) IconButton(tooltip: 'Editar', onPressed: () => _edit(c), icon: const Icon(Icons.edit_outlined)),
                if (c != null)
                  PopupMenuButton<String>(
                    onSelected: (_) => _delete(c),
                    itemBuilder: (_) => const [PopupMenuItem(value: 'delete', child: Text('Eliminar cliente'))],
                  ),
              ],
            ),
            body: snapshot.connectionState != ConnectionState.done
                ? const LoadingView()
                : snapshot.hasError
                    ? ErrorView(error: snapshot.error!, onRetry: () => setState(() => _future = _load()))
                    : ListView(padding: const EdgeInsets.all(16), children: [
                        Row(children: [
                          Expanded(child: Text(c!['name']?.toString() ?? '', style: theme.textTheme.headlineSmall)),
                          partnerStatus.chip(context, c['status'] ?? 'active'),
                        ]),
                        const SizedBox(height: 12),
                        SectionCard(title: 'Contacto', children: [
                          InfoRow('Correo', c['email']?.toString()),
                          InfoRow('Teléfono', c['phone']?.toString()),
                          InfoRow('Dirección', [c['address'], c['city'], c['state'], c['postal_code'], c['country']].where((v) => v != null && v.toString().isNotEmpty).join(', ')),
                        ]),
                        const SizedBox(height: 12),
                        SectionCard(title: 'Datos fiscales y crédito', children: [
                          InfoRow('Razón social', c['legal_name']?.toString()),
                          InfoRow('RFC', c['tax_id']?.toString()),
                          InfoRow('Régimen fiscal', fiscalRegimes[c['fiscal_regime']] ?? c['fiscal_regime']?.toString()),
                          InfoRow('Uso de CFDI', cfdiUses[c['cfdi_use']] ?? c['cfdi_use']?.toString()),
                          InfoRow('C.P. fiscal', c['tax_zip_code']?.toString()),
                          InfoRow('Límite de crédito', formatMoney(c['credit_limit'])),
                          InfoRow('Crédito disponible', c['available_credit'] == null ? null : formatMoney(c['available_credit'])),
                          InfoRow('Notas', c['notes']?.toString()),
                        ]),
                        if (_history != null) ...[
                          const SizedBox(height: 12),
                          FutureBuilder<List<Map<String, dynamic>>>(
                            future: _history,
                            builder: (context, h) => SectionCard(title: 'Ventas y devoluciones', children: [
                              if (h.connectionState != ConnectionState.done) const Padding(padding: EdgeInsets.all(16), child: LinearProgressIndicator()),
                              if (h.hasData && h.data!.isEmpty) const Padding(padding: EdgeInsets.fromLTRB(16, 0, 16, 8), child: Text('Sin movimientos.')),
                              for (final item in h.data ?? const <Map<String, dynamic>>[])
                                ListTile(
                                  dense: true,
                                  leading: Icon(item['type'] == 'return' ? Icons.keyboard_return : Icons.receipt_long_outlined),
                                  title: Text('${item['type'] == 'return' ? 'Devolución' : 'Venta'} ${item['number'] ?? ''}'),
                                  subtitle: Text('${formatDate(item['date'])} · ${(item['type'] == 'return' ? returnStatus : saleStatus).label(item['status'])}'),
                                  trailing: Text(formatMoney(item['amount'])),
                                  onTap: () => context.push('${item['type'] == 'return' ? '/clients/returns' : '/clients/orders'}/${item['id']}'),
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
