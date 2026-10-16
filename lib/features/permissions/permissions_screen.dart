import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/api_client.dart';
import '../../core/user_profile.dart';
import '../../widgets/app_shell.dart';
import '../../widgets/async_states.dart';
import '../../widgets/form_fields.dart';
import '../users/users_screen.dart';

const _modules = [
  ('pos', 'POS / Caja (leer, cobrar/abrir, cerrar)'),
  ('products', 'Productos'),
  ('categories', 'Categorías'),
  ('sales', 'Ventas'),
  ('purchases', 'Compras'),
  ('inventory', 'Inventario'),
  ('movements', 'Movimientos'),
  ('warehouses', 'Almacenes'),
  ('reports', 'Reportes'),
  ('sale_invoices', 'Facturación'),
];
const _actions = [('can_read', 'Ver'), ('can_create', 'Crear'), ('can_update', 'Editar'), ('can_delete', 'Borrar')];

/// Permisos por módulo de cada usuario (mismo esquema que la web). Facturación
/// solo se puede otorgar si la empresa tiene ese módulo contratado. El permiso
/// de Backoffice se cambia en la web (pide credenciales de la plataforma).
class PermissionsScreen extends StatefulWidget {
  const PermissionsScreen({super.key});

  @override
  State<PermissionsScreen> createState() => _PermissionsScreenState();
}

class _PermissionsScreenState extends State<PermissionsScreen> {
  late Future<List<Map<String, dynamic>>> _users = context.read<ApiClient>().get('/users').then(asMapList);
  String _search = '';

  @override
  Widget build(BuildContext context) {
    return ModuleScaffold(
      title: 'Permisos',
      body: FutureBuilder<List<Map<String, dynamic>>>(
        future: _users,
        builder: (context, snapshot) {
          if (snapshot.connectionState != ConnectionState.done) return const LoadingView();
          if (snapshot.hasError) {
            return ErrorView(error: snapshot.error!, onRetry: () => setState(() => _users = context.read<ApiClient>().get('/users').then(asMapList)));
          }
          final users = snapshot.data!.where((u) => '${u['first_name']} ${u['last_name']} ${u['email']}'.toLowerCase().contains(_search.toLowerCase())).toList();
          return ListView(padding: const EdgeInsets.all(16), children: [
            const Text('Elige un usuario para definir qué puede ver, crear, editar o borrar en cada módulo.'),
            const SizedBox(height: 12),
            TextField(onChanged: (v) => setState(() => _search = v), decoration: const InputDecoration(hintText: 'Buscar usuario', prefixIcon: Icon(Icons.search))),
            const SizedBox(height: 12),
            for (final u in users)
              Card(
                margin: const EdgeInsets.only(bottom: 8),
                child: ListTile(
                  title: Text('${u['first_name'] ?? ''} ${u['last_name'] ?? ''}'.trim()),
                  subtitle: Text(u['email']?.toString() ?? ''),
                  trailing: StatusChip(roleLabels[u['role']] ?? '${u['role']}'),
                  onTap: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => _UserPermissions(user: u))),
                ),
              ),
          ]);
        },
      ),
    );
  }
}

class _UserPermissions extends StatefulWidget {
  const _UserPermissions({required this.user});
  final Map<String, dynamic> user;

  @override
  State<_UserPermissions> createState() => _UserPermissionsState();
}

class _UserPermissionsState extends State<_UserPermissions> {
  final _matrix = <String, Map<String, bool>>{for (final (key, _) in _modules) key: {for (final (a, _) in _actions) a: false}};
  bool _invoicing = false;
  bool _loading = true;
  bool _saving = false;
  bool _dirty = false;
  Object? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final api = context.read<ApiClient>();
    try {
      final results = await Future.wait([api.get('/users/${widget.user['id']}/module_permissions'), api.get('/billing')]);
      for (final p in asMapList(results[0])) {
        final row = _matrix[p['module_name']];
        if (row == null) continue;
        for (final (a, _) in _actions) {
          row[a] = p[a] == true;
        }
      }
      _invoicing = asMap(asMap(results[1])['invoicing'])['active'] == true;
    } catch (error) {
      _error = error;
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _save() async {
    setState(() => _saving = true);
    try {
      await context.read<ApiClient>().put('/users/${widget.user['id']}/update_module_permissions', {
        'permissions': {
          for (final entry in _matrix.entries)
            if (entry.key != 'sale_invoices' || _invoicing) entry.key: entry.value,
        },
      });
      if (!mounted) return;
      setState(() => _dirty = false);
      showMessage(context, 'Permisos guardados');
    } catch (error) {
      if (mounted) showError(context, error);
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(title: Text('${widget.user['first_name'] ?? ''} ${widget.user['last_name'] ?? ''}'.trim())),
      body: _loading
          ? const LoadingView()
          : _error != null
              ? ErrorView(error: _error!)
              : ListView(padding: const EdgeInsets.all(16), children: [
                  if (widget.user['role'] == 'admin')
                    const Card(child: Padding(padding: EdgeInsets.all(12), child: Text('Los administradores tienen acceso a todos los módulos excepto Facturación, que requiere permiso explícito.'))),
                  for (final (key, label) in _modules)
                    Card(
                      margin: const EdgeInsets.only(bottom: 8),
                      child: Padding(
                        padding: const EdgeInsets.fromLTRB(12, 8, 12, 4),
                        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                          Text(label, style: theme.textTheme.titleSmall),
                          if (key == 'sale_invoices' && !_invoicing)
                            const Padding(padding: EdgeInsets.only(top: 4), child: Text('Disponible cuando la empresa tenga Facturación activa.'))
                          else
                            Wrap(spacing: 4, children: [
                              for (final (action, actionLabel) in _actions)
                                FilterChip(
                                  label: Text(actionLabel),
                                  selected: _matrix[key]![action]!,
                                  onSelected: (v) => setState(() {
                                    _matrix[key]![action] = v;
                                    _dirty = true;
                                  }),
                                ),
                            ]),
                        ]),
                      ),
                    ),
                  const SizedBox(height: 80),
                ]),
      bottomNavigationBar: _loading || _error != null
          ? null
          : SafeArea(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: FilledButton(onPressed: _saving || !_dirty ? null : _save, child: Text(_saving ? 'Guardando…' : 'Guardar permisos')),
              ),
            ),
    );
  }
}
