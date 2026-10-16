import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../../core/api_client.dart';
import '../../core/catalogs.dart';
import '../../core/formatters.dart';
import '../../core/user_profile.dart';
import '../../widgets/app_shell.dart';
import '../../widgets/async_states.dart';
import '../../widgets/form_fields.dart';

/// Formulario de almacén (alta y edición).
Future<bool?> showWarehouseForm(BuildContext context, [Map<String, dynamic>? warehouse]) => showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (_) => _WarehouseForm(warehouse: warehouse),
    );

class WarehousesScreen extends StatefulWidget {
  const WarehousesScreen({super.key});

  @override
  State<WarehousesScreen> createState() => _WarehousesScreenState();
}

class _WarehousesScreenState extends State<WarehousesScreen> {
  late Future<List<Map<String, dynamic>>> _future = _load();

  Future<List<Map<String, dynamic>>> _load() async {
    context.read<Catalogs>().invalidate(warehouses: true);
    return asMapList(await context.read<ApiClient>().get('/warehouses'));
  }

  void _reload() => setState(() => _future = _load());

  @override
  Widget build(BuildContext context) {
    return ModuleScaffold(
      title: 'Almacenes',
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () async {
          if (await showWarehouseForm(context) == true) _reload();
        },
        icon: const Icon(Icons.add),
        label: const Text('Nuevo'),
      ),
      body: FutureBuilder<List<Map<String, dynamic>>>(
        future: _future,
        builder: (context, snapshot) {
          if (snapshot.connectionState != ConnectionState.done) return const LoadingView();
          if (snapshot.hasError) return ErrorView(error: snapshot.error!, onRetry: _reload);
          final warehouses = snapshot.data!;
          return RefreshIndicator(
            onRefresh: () async => _reload(),
            child: ListView(padding: const EdgeInsets.fromLTRB(16, 12, 16, 96), children: [
              if (warehouses.isEmpty) const MessageView(icon: Icons.warehouse_outlined, title: 'Sin almacenes'),
              for (final w in warehouses)
                Card(
                  margin: const EdgeInsets.only(bottom: 8),
                  child: ListTile(
                    leading: const Icon(Icons.warehouse_outlined),
                    title: Text(w['name']?.toString() ?? ''),
                    subtitle: Text('${w['location'] ?? ''} · ${formatNumber(w['products_count'] ?? 0)} productos'),
                    trailing: StatusChip(w['is_active'] == false ? 'Inactivo' : 'Activo',
                        color: w['is_active'] == false ? Theme.of(context).colorScheme.outline : Colors.green.shade700),
                    onTap: () async {
                      final changed = await context.push<bool>('/warehouses/${w['id']}');
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

class _WarehouseForm extends StatefulWidget {
  const _WarehouseForm({this.warehouse});
  final Map<String, dynamic>? warehouse;

  @override
  State<_WarehouseForm> createState() => _WarehouseFormState();
}

class _WarehouseFormState extends State<_WarehouseForm> {
  late final _name = TextEditingController(text: widget.warehouse?['name']?.toString());
  late final _location = TextEditingController(text: widget.warehouse?['location']?.toString());
  late final _description = TextEditingController(text: widget.warehouse?['description']?.toString());
  late bool _active = widget.warehouse?['is_active'] != false;
  bool _busy = false;
  String? _error;

  Future<void> _save() async {
    if (_name.text.trim().isEmpty || _location.text.trim().isEmpty) {
      setState(() => _error = 'Escribe el nombre y la ubicación.');
      return;
    }
    setState(() => _busy = true);
    final body = {
      'warehouse': {'name': _name.text.trim(), 'location': _location.text.trim(), 'description': _description.text.trim(), 'is_active': _active},
    };
    try {
      final api = context.read<ApiClient>();
      widget.warehouse == null ? await api.post('/warehouses', body) : await api.put('/warehouses/${widget.warehouse!['id']}', body);
      if (mounted) {
        context.read<Catalogs>().invalidate(warehouses: true);
        Navigator.pop(context, true);
      }
    } catch (error) {
      if (mounted) setState(() => _error = error.toString());
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => Padding(
        padding: EdgeInsets.fromLTRB(16, 16, 16, MediaQuery.of(context).viewInsets.bottom + 16),
        child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Text(widget.warehouse == null ? 'Nuevo almacén' : 'Editar almacén', style: Theme.of(context).textTheme.titleLarge),
          const SizedBox(height: 12),
          if (_error != null) Text(_error!, style: TextStyle(color: Theme.of(context).colorScheme.error)),
          TextField(controller: _name, decoration: const InputDecoration(labelText: 'Nombre *')),
          const SizedBox(height: 12),
          TextField(controller: _location, decoration: const InputDecoration(labelText: 'Ubicación *', hintText: 'Ciudad o dirección')),
          const SizedBox(height: 12),
          TextField(controller: _description, maxLines: 2, decoration: const InputDecoration(labelText: 'Descripción')),
          SwitchListTile(contentPadding: EdgeInsets.zero, title: const Text('Activo'), value: _active, onChanged: (v) => setState(() => _active = v)),
          FilledButton(onPressed: _busy ? null : _save, child: Text(_busy ? 'Guardando…' : 'Guardar')),
        ]),
      );
}
