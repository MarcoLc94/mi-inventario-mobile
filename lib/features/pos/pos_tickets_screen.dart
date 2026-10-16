import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/api_client.dart';
import '../../core/formatters.dart';
import '../../core/user_profile.dart';
import '../../widgets/app_shell.dart';
import '../../widgets/paged_list.dart';
import 'pos_models.dart';
import 'pos_screen.dart';

/// Ventas y tickets del punto de venta (GET /pos/sales, 20 por página).
class PosTicketsScreen extends StatelessWidget {
  const PosTicketsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return ModuleScaffold(
      title: 'Tickets',
      body: PagedList(
        fetch: (page) async {
          final data = asMap(await context.read<ApiClient>().get('/pos/sales', query: {'page': page}));
          final total = (data['total'] as num?)?.toInt() ?? 0;
          return PageResult(asMapList(data['data']), total, (total / 20).ceil());
        },
        emptyIcon: Icons.confirmation_number_outlined,
        emptyTitle: 'Sin ventas',
        itemBuilder: (context, sale, _) => Card(
          margin: const EdgeInsets.only(bottom: 8),
          child: ListTile(
            title: Text(sale['folio']?.toString() ?? ''),
            subtitle: Text('${formatDateTime(sale['created_at'])} · ${posMethods[sale['payment_method']] ?? sale['payment_method']}\n'
                '${asMap(sale['receipt'])['client'] ?? ''}'),
            isThreeLine: true,
            trailing: Column(mainAxisAlignment: MainAxisAlignment.center, crossAxisAlignment: CrossAxisAlignment.end, children: [
              Text(money(sale['total']), style: Theme.of(context).textTheme.titleSmall),
              const Icon(Icons.picture_as_pdf_outlined, size: 18),
            ]),
            onTap: () => openTicket(context, sale),
          ),
        ),
      ),
    );
  }
}
