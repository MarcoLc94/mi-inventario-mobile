import 'dart:async';

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../../core/api_client.dart';
import '../../core/formatters.dart';
import '../../core/user_profile.dart';
import '../../widgets/app_shell.dart';
import '../../widgets/paged_list.dart';
import '../../widgets/status.dart';

class PurchaseOrdersScreen extends StatefulWidget {
  const PurchaseOrdersScreen({super.key});

  @override
  State<PurchaseOrdersScreen> createState() => _PurchaseOrdersScreenState();
}

class _PurchaseOrdersScreenState extends State<PurchaseOrdersScreen> {
  final _listKey = GlobalKey<PagedListState>();
  String? _status;
  String _search = '';
  Timer? _debounce;

  @override
  void dispose() {
    _debounce?.cancel();
    super.dispose();
  }

  Future<PageResult> _fetch(int page) async {
    final text = _search.trim();
    return PageResult.fromJson(await context.read<ApiClient>().get('/purchase_orders', query: {
      'page': page,
      'per_page': 20,
      'sort_by': 'created_at',
      'sort_dir': 'desc',
      'status': _status,
      if (text.isNotEmpty) (RegExp(r'\d').hasMatch(text) ? 'order_number' : 'supplier_name'): text,
    }));
  }

  @override
  Widget build(BuildContext context) {
    return ModuleScaffold(
      title: 'Órdenes de compra',
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () async {
          final created = await context.push<bool>('/suppliers/orders/create');
          if (created == true) _listKey.currentState?.reload();
        },
        icon: const Icon(Icons.add),
        label: const Text('Nueva'),
      ),
      body: PagedList(
        key: _listKey,
        queryKey: (_status, _search),
        fetch: _fetch,
        emptyIcon: Icons.shopping_cart_outlined,
        emptyTitle: 'Sin órdenes de compra',
        header: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          TextField(
            onChanged: (v) {
              _debounce?.cancel();
              _debounce = Timer(const Duration(milliseconds: 400), () => setState(() => _search = v));
            },
            decoration: const InputDecoration(hintText: 'Buscar por folio o proveedor', prefixIcon: Icon(Icons.search)),
          ),
          const SizedBox(height: 8),
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(children: [
              for (final entry in {null: 'Todas', ...purchaseStatus.labels}.entries)
                Padding(
                  padding: const EdgeInsets.only(right: 8),
                  child: ChoiceChip(label: Text(entry.value), selected: _status == entry.key, onSelected: (_) => setState(() => _status = entry.key)),
                ),
            ]),
          ),
          const SizedBox(height: 8),
        ]),
        itemBuilder: (context, order, reload) => Card(
          margin: const EdgeInsets.only(bottom: 8),
          child: ListTile(
            title: Text('Compra ${order['order_number'] ?? '#${order['id']}'}'),
            subtitle: Text('${asMap(order['supplier'])['name'] ?? 'Sin proveedor'}\n'
                '${formatDate(order['order_date'])} · entrega ${formatDate(order['expected_delivery_date'])}'),
            isThreeLine: true,
            trailing: Column(mainAxisAlignment: MainAxisAlignment.center, crossAxisAlignment: CrossAxisAlignment.end, children: [
              Text(formatMoney(order['total'] ?? order['total_amount']), style: Theme.of(context).textTheme.titleSmall),
              purchaseStatus.chip(context, order['status']),
            ]),
            onTap: () async {
              final changed = await context.push<bool>('/suppliers/orders/${order['id']}');
              if (changed == true) reload();
            },
          ),
        ),
      ),
    );
  }
}
