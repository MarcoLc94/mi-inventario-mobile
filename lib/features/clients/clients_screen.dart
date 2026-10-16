import 'dart:async';

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../../core/api_client.dart';
import '../../widgets/app_shell.dart';
import '../../widgets/paged_list.dart';
import '../../widgets/status.dart';
import 'client_form_screen.dart';

class ClientsScreen extends StatefulWidget {
  const ClientsScreen({super.key});

  @override
  State<ClientsScreen> createState() => _ClientsScreenState();
}

class _ClientsScreenState extends State<ClientsScreen> {
  final _listKey = GlobalKey<PagedListState>();
  String _search = '';
  Timer? _debounce;

  @override
  void dispose() {
    _debounce?.cancel();
    super.dispose();
  }

  Future<PageResult> _fetch(int page) async => PageResult.fromJson(await context.read<ApiClient>().get('/clients', query: {
        'page': page,
        'per_page': 25,
        'sort_by': 'name',
        'sort_dir': 'asc',
        'name': _search.trim(),
      }));

  Future<void> _create() async {
    final created = await Navigator.of(context).push<Map<String, dynamic>>(MaterialPageRoute(builder: (_) => const ClientFormScreen()));
    if (created != null) _listKey.currentState?.reload();
  }

  @override
  Widget build(BuildContext context) {
    return ModuleScaffold(
      title: 'Clientes',
      floatingActionButton: FloatingActionButton.extended(onPressed: _create, icon: const Icon(Icons.add), label: const Text('Nuevo')),
      body: PagedList(
        key: _listKey,
        queryKey: _search,
        fetch: _fetch,
        emptyIcon: Icons.people_outline,
        emptyTitle: 'Sin clientes',
        header: Padding(
          padding: const EdgeInsets.only(bottom: 8),
          child: TextField(
            onChanged: (v) {
              _debounce?.cancel();
              _debounce = Timer(const Duration(milliseconds: 400), () => setState(() => _search = v));
            },
            decoration: const InputDecoration(hintText: 'Buscar cliente', prefixIcon: Icon(Icons.search)),
          ),
        ),
        itemBuilder: (context, c, reload) => Card(
          margin: const EdgeInsets.only(bottom: 8),
          child: ListTile(
            leading: CircleAvatar(child: Text((c['name']?.toString() ?? '?').characters.first.toUpperCase())),
            title: Text(c['name']?.toString() ?? ''),
            subtitle: Text([c['phone'], c['email'], c['tax_id']].where((v) => v != null && v.toString().isNotEmpty).join(' · ')),
            trailing: c['status'] == null || c['status'] == 'active' ? null : partnerStatus.chip(context, c['status']),
            onTap: () async {
              final changed = await context.push<bool>('/clients/${c['id']}');
              if (changed == true) reload();
            },
          ),
        ),
      ),
    );
  }
}
