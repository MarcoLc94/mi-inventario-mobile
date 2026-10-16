import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/api_client.dart';
import '../../core/catalogs.dart';
import '../../core/user_profile.dart';
import '../../widgets/app_shell.dart';
import '../../widgets/async_states.dart';
import '../../widgets/form_fields.dart';

class CategoriesScreen extends StatefulWidget {
  const CategoriesScreen({super.key});

  @override
  State<CategoriesScreen> createState() => _CategoriesScreenState();
}

class _CategoriesScreenState extends State<CategoriesScreen> {
  late Future<List<Map<String, dynamic>>> _future = _load();
  String _filter = '';

  Future<List<Map<String, dynamic>>> _load() async => asMapList(await context.read<ApiClient>().get('/categories'));

  void _reload() {
    context.read<Catalogs>().invalidate(categories: true);
    setState(() => _future = _load());
  }

  Future<void> _create() async {
    final created = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (_) => const _CategoryForm(),
    );
    if (created == true) _reload();
  }

  Future<void> _delete(Map<String, dynamic> category) async {
    final ok = await confirm(context,
        title: 'Eliminar categoría', message: '¿Seguro que deseas eliminar "${category['name']}"?', action: 'Eliminar', destructive: true);
    if (!ok || !mounted) return;
    try {
      await context.read<ApiClient>().delete('/categories/${category['id']}');
      _reload();
    } catch (error) {
      if (mounted) showError(context, error);
    }
  }

  @override
  Widget build(BuildContext context) {
    return ModuleScaffold(
      title: 'Categorías',
      floatingActionButton: FloatingActionButton.extended(onPressed: _create, icon: const Icon(Icons.add), label: const Text('Crear')),
      body: FutureBuilder<List<Map<String, dynamic>>>(
        future: _future,
        builder: (context, snapshot) {
          if (snapshot.connectionState != ConnectionState.done) return const LoadingView();
          if (snapshot.hasError) return ErrorView(error: snapshot.error!, onRetry: _reload);
          final items = snapshot.data!
              .where((c) => '${c['name']} ${c['description'] ?? ''}'.toLowerCase().contains(_filter.toLowerCase()))
              .toList();
          return RefreshIndicator(
            onRefresh: () async => _reload(),
            child: ListView(padding: const EdgeInsets.fromLTRB(16, 12, 16, 96), children: [
              TextField(
                onChanged: (value) => setState(() => _filter = value),
                decoration: const InputDecoration(hintText: 'Buscar categoría', prefixIcon: Icon(Icons.search)),
              ),
              const SizedBox(height: 12),
              if (items.isEmpty)
                const Padding(padding: EdgeInsets.all(32), child: Center(child: Text('Sin categorías')))
              else
                Card(
                  child: Column(children: [
                    for (final c in items)
                      ListTile(
                        leading: const Icon(Icons.category_outlined),
                        title: Text(c['name']?.toString() ?? ''),
                        subtitle: (c['description']?.toString() ?? '').isEmpty ? null : Text(c['description'].toString()),
                        trailing: IconButton(tooltip: 'Eliminar', icon: const Icon(Icons.delete_outline), onPressed: () => _delete(c)),
                      ),
                  ]),
                ),
            ]),
          );
        },
      ),
    );
  }
}

class _CategoryForm extends StatefulWidget {
  const _CategoryForm();

  @override
  State<_CategoryForm> createState() => _CategoryFormState();
}

class _CategoryFormState extends State<_CategoryForm> {
  final _name = TextEditingController();
  final _description = TextEditingController();
  bool _saving = false;
  String? _error;

  Future<void> _save() async {
    if (_name.text.trim().isEmpty) return;
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      await context.read<ApiClient>().post('/categories', {
        'category': {'name': _name.text.trim(), 'description': _description.text.trim(), 'usable': false},
      });
      if (mounted) Navigator.pop(context, true);
    } catch (error) {
      if (mounted) setState(() => _error = error.toString());
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) => Padding(
        padding: EdgeInsets.fromLTRB(16, 16, 16, MediaQuery.of(context).viewInsets.bottom + 16),
        child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Text('Crear categoría', style: Theme.of(context).textTheme.titleLarge),
          const Text('Agrupa tus productos para organizarlos y filtrarlos más fácil.'),
          const SizedBox(height: 16),
          if (_error != null) Text(_error!, style: TextStyle(color: Theme.of(context).colorScheme.error)),
          TextField(
            controller: _name,
            autofocus: true,
            onChanged: (_) => setState(() {}),
            decoration: const InputDecoration(labelText: 'Nombre *', hintText: 'Ej. Bebidas'),
          ),
          const SizedBox(height: 12),
          TextField(controller: _description, maxLines: 3, decoration: const InputDecoration(labelText: 'Descripción (opcional)')),
          const SizedBox(height: 16),
          FilledButton(onPressed: _saving || _name.text.trim().isEmpty ? null : _save, child: Text(_saving ? 'Guardando…' : 'Guardar')),
        ]),
      );
}
