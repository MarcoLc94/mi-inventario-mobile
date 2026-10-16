import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../../core/api_client.dart';
import '../../core/formatters.dart';
import '../../core/user_profile.dart';
import '../../widgets/app_shell.dart';
import '../../widgets/paged_list.dart';
import 'cfdi_catalogs.dart';

/// Lista de complementos de pago, notas de crédito o facturas globales.
class CfdiDocumentsScreen extends StatefulWidget {
  const CfdiDocumentsScreen({super.key, required this.kind});
  final CfdiKind kind;

  @override
  State<CfdiDocumentsScreen> createState() => _CfdiDocumentsScreenState();
}

class _CfdiDocumentsScreenState extends State<CfdiDocumentsScreen> {
  final _listKey = GlobalKey<PagedListState>();
  String? _status;

  String _subtitle(Map<String, dynamic> doc) {
    final invoice = asMap(doc['sale_invoice']);
    return switch (widget.kind) {
      CfdiKind.payment => '${asMap(invoice['client'])['name'] ?? '—'} · Factura ${cfdiFolio(invoice)}\n'
          'Pago ${formatDate(doc['payment_date'])} · parcialidad ${doc['partiality_number']} · saldo ${formatMoney(doc['remaining_balance'])}',
      CfdiKind.creditNote => '${asMap(invoice['client'])['name'] ?? '—'} · Factura ${cfdiFolio(invoice)}\n${doc['relation_label'] ?? ''} · ${formatDate(doc['created_at'])}',
      CfdiKind.globalInvoice => '${formatDate(doc['period_start'])} – ${formatDate(doc['period_end'])}\n${doc['periodicity_label'] ?? ''} · ${doc['tickets_count'] ?? 0} tickets',
    };
  }

  @override
  Widget build(BuildContext context) {
    final kind = widget.kind;
    return ModuleScaffold(
      title: kind.plural,
      floatingActionButton: kind == CfdiKind.globalInvoice
          ? FloatingActionButton.extended(
              onPressed: () async {
                await context.push('/cfdis/factura-global/nueva');
                _listKey.currentState?.reload();
              },
              icon: const Icon(Icons.add),
              label: const Text('Emitir'),
            )
          : null,
      body: PagedList(
        key: _listKey,
        queryKey: _status,
        fetch: (page) async => PageResult.fromJson(await context.read<ApiClient>().get('/${kind.apiPath}', query: {'page': page, 'per_page': 20, 'status': _status})),
        emptyIcon: Icons.receipt_long_outlined,
        emptyTitle: 'Sin ${kind.plural.toLowerCase()}',
        emptyMessage: kind.intro,
        header: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Padding(padding: const EdgeInsets.only(bottom: 8), child: Text(kind.intro, style: Theme.of(context).textTheme.bodySmall)),
          const CfdiSandboxBanner(),
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(children: [
              for (final entry in {null: 'Todos', ...cfdiStatusLabels}.entries)
                Padding(
                  padding: const EdgeInsets.only(right: 8),
                  child: ChoiceChip(label: Text(entry.value), selected: _status == entry.key, onSelected: (_) => setState(() => _status = entry.key)),
                ),
            ]),
          ),
          const SizedBox(height: 8),
        ]),
        itemBuilder: (context, doc, reload) => Card(
          margin: const EdgeInsets.only(bottom: 8),
          child: ListTile(
            title: Text(cfdiFolio(doc)),
            subtitle: Text(_subtitle(doc)),
            isThreeLine: true,
            trailing: Column(mainAxisAlignment: MainAxisAlignment.center, crossAxisAlignment: CrossAxisAlignment.end, children: [
              Text(formatMoney(doc['amount'] ?? doc['total']), style: Theme.of(context).textTheme.titleSmall),
              cfdiStatusChip(context, doc['status']),
            ]),
            onTap: () async {
              await context.push('${kind.route}/${doc['id']}');
              reload();
            },
          ),
        ),
      ),
    );
  }
}
