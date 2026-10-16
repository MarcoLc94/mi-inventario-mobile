import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../../core/api_client.dart';
import '../../core/user_profile.dart';
import '../../widgets/app_shell.dart';
import '../../widgets/async_states.dart';
import '../../widgets/status.dart';
import 'supplier_form_screen.dart';

class SuppliersScreen extends StatefulWidget {
  const SuppliersScreen({super.key});

  @override
  State<SuppliersScreen> createState() => _SuppliersScreenState();
}

class _SuppliersScreenState extends State<SuppliersScreen> {
  late Future<List<Map<String, dynamic>>> _future = _load();
  String _search = '';

  Future<List<Map<String, dynamic>>> _load() async => asMapList(await context.read<ApiClient>().get('/suppliers'));
  void _reload() => setState(() => _future = _load());

  Future<void> _create() async {
    final created = await Navigator.of(context).push<Map<String, dynamic>>(MaterialPageRoute(builder: (_) => const SupplierFormScreen()));
    if (created != null) _reload();
  }

  @override
  Widget build(BuildContext context) {
    return ModuleScaffold(
      title: 'Proveedores',
      floatingActionButton: FloatingActionButton.extended(onPressed: _create, icon: const Icon(Icons.add), label: const Text('Nuevo')),
      body: FutureBuilder<List<Map<String, dynamic>>>(
        future: _future,
        builder: (context, snapshot) {
          if (snapshot.connectionState != ConnectionState.done) return const LoadingView();
          if (snapshot.hasError) return ErrorView(error: snapshot.error!, onRetry: _reload);
          final items = snapshot.data!
              .where((s) => '${s['name']} ${s['contact_name'] ?? ''} ${s['tax_id'] ?? ''}'.toLowerCase().contains(_search.toLowerCase()))
              .toList();
          return RefreshIndicator(
            onRefresh: () async => _reload(),
            child: ListView(padding: const EdgeInsets.fromLTRB(16, 12, 16, 96), children: [
              TextField(
                onChanged: (v) => setState(() => _search = v),
                decoration: const InputDecoration(hintText: 'Buscar por nombre, razón social o RFC', prefixIcon: Icon(Icons.search)),
              ),
              const SizedBox(height: 12),
              if (items.isEmpty) const MessageView(icon: Icons.local_shipping_outlined, title: 'Sin proveedores'),
              for (final s in items)
                Card(
                  margin: const EdgeInsets.only(bottom: 8),
                  child: ListTile(
                    title: Text(s['name']?.toString() ?? ''),
                    subtitle: Text([s['contact_name'], s['tax_id'], s['phone']].where((v) => v != null && v.toString().isNotEmpty).join(' · ')),
                    trailing: partnerStatus.chip(context, s['status']),
                    onTap: () async {
                      final changed = await context.push<bool>('/suppliers/detail/${s['id']}');
                      if (changed == true) _reload();
                    },
                  ),
                ),
            ]),
          );
        },
      ),
    );
  }
}
