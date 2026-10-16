import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../../core/api_client.dart';
import '../../core/formatters.dart';
import '../../core/user_profile.dart';
import '../../widgets/app_shell.dart';
import '../../widgets/paged_list.dart';
import 'cfdi_catalogs.dart';

/// Facturas de venta (CFDI de ingreso). Se crean desde una orden de venta enviada.
class SaleInvoicesScreen extends StatefulWidget {
  const SaleInvoicesScreen({super.key});

  @override
  State<SaleInvoicesScreen> createState() => _SaleInvoicesScreenState();
}

class _SaleInvoicesScreenState extends State<SaleInvoicesScreen> {
  String? _status;

  @override
  Widget build(BuildContext context) {
    return ModuleScaffold(
      title: 'Facturas',
      body: PagedList(
        queryKey: _status,
        fetch: (page) async => PageResult.fromJson(await context.read<ApiClient>().get('/sale_invoices', query: {'page': page, 'per_page': 20, 'status': _status})),
        emptyIcon: Icons.description_outlined,
        emptyTitle: 'Sin facturas',
        emptyMessage: 'Factura una orden de venta enviada desde su detalle.',
        header: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          const CfdiSandboxBanner(),
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(children: [
              for (final entry in {null: 'Todas', ...cfdiStatusLabels}.entries)
                Padding(
                  padding: const EdgeInsets.only(right: 8),
                  child: ChoiceChip(label: Text(entry.value), selected: _status == entry.key, onSelected: (_) => setState(() => _status = entry.key)),
                ),
            ]),
          ),
          const SizedBox(height: 8),
        ]),
        itemBuilder: (context, inv, reload) => Card(
          margin: const EdgeInsets.only(bottom: 8),
          child: ListTile(
            title: Text('Factura ${cfdiFolio(inv)}'),
            subtitle: Text('${asMap(asMap(inv['sale_order'])['client'])['name'] ?? '—'}\n${formatDate(inv['invoice_date'])} · ${inv['payment_method'] ?? ''}'),
            isThreeLine: true,
            trailing: Column(mainAxisAlignment: MainAxisAlignment.center, crossAxisAlignment: CrossAxisAlignment.end, children: [
              Text(formatMoney(inv['total']), style: Theme.of(context).textTheme.titleSmall),
              cfdiStatusChip(context, inv['status']),
            ]),
            onTap: () async {
              await context.push('/cfdis/facturas/${inv['id']}');
              reload();
            },
          ),
        ),
      ),
    );
  }
}
