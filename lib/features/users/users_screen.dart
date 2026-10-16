import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../../core/api_client.dart';
import '../../core/user_profile.dart';
import '../../widgets/app_shell.dart';
import '../../widgets/async_states.dart';
import '../../widgets/form_fields.dart';

const roleLabels = {
  'admin': 'Admin',
  'manager': 'Gerente',
  'auditor': 'Auditor',
  'warehouse': 'Almacén',
  'operator': 'Operador',
  'user': 'Empleado',
  'maintance': 'Técnico',
};

/// Roles que se pueden asignar (mismos que la web, CreateUser.tsx).
const assignableRoles = ['user', 'operator', 'admin', 'manager', 'auditor', 'warehouse'];

class UsersScreen extends StatefulWidget {
  const UsersScreen({super.key});

  @override
  State<UsersScreen> createState() => _UsersScreenState();
}

class _UsersScreenState extends State<UsersScreen> {
  late Future<List<Map<String, dynamic>>> _future = _load();
  String _search = '';

  Future<List<Map<String, dynamic>>> _load() async => asMapList(await context.read<ApiClient>().get('/users'));
  void _reload() => setState(() => _future = _load());

  Future<void> _create() async {
    final created = await showModalBottomSheet<bool>(context: context, isScrollControlled: true, useSafeArea: true, builder: (_) => const _CreateUser());
    if (created == true) _reload();
  }

  @override
  Widget build(BuildContext context) {
    return ModuleScaffold(
      title: 'Usuarios',
      floatingActionButton: FloatingActionButton.extended(onPressed: _create, icon: const Icon(Icons.person_add_alt), label: const Text('Nuevo')),
      body: FutureBuilder<List<Map<String, dynamic>>>(
        future: _future,
        builder: (context, snapshot) {
          if (snapshot.connectionState != ConnectionState.done) return const LoadingView();
          if (snapshot.hasError) return ErrorView(error: snapshot.error!, onRetry: _reload);
          final users = snapshot.data!
              .where((u) => '${u['first_name']} ${u['last_name']} ${u['email']}'.toLowerCase().contains(_search.toLowerCase()))
              .toList();
          return RefreshIndicator(
            onRefresh: () async => _reload(),
            child: ListView(padding: const EdgeInsets.fromLTRB(16, 12, 16, 96), children: [
              TextField(onChanged: (v) => setState(() => _search = v), decoration: const InputDecoration(hintText: 'Buscar usuario', prefixIcon: Icon(Icons.search))),
              const SizedBox(height: 12),
              for (final u in users)
                Card(
                  margin: const EdgeInsets.only(bottom: 8),
                  child: ListTile(
                    leading: CircleAvatar(
                      backgroundImage: (u['profile_picture_url']?.toString().isNotEmpty ?? false) ? NetworkImage(u['profile_picture_url'].toString()) : null,
                      child: (u['profile_picture_url']?.toString().isNotEmpty ?? false) ? null : Text((u['first_name']?.toString() ?? '?').characters.first.toUpperCase()),
                    ),
                    title: Text('${u['first_name'] ?? ''} ${u['last_name'] ?? ''}'.trim()),
                    subtitle: Text(u['email']?.toString() ?? ''),
                    trailing: StatusChip(roleLabels[u['role']] ?? '${u['role']}'),
                    onTap: () async {
                      final changed = await context.push<bool>('/user-detail/${u['id']}');
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

class _CreateUser extends StatefulWidget {
  const _CreateUser();

  @override
  State<_CreateUser> createState() => _CreateUserState();
}

class _CreateUserState extends State<_CreateUser> {
  final _first = TextEditingController();
  final _last = TextEditingController();
  final _email = TextEditingController();
  final _password = TextEditingController();
  final _confirm = TextEditingController();
  String _role = 'user';
  bool _busy = false;
  bool _obscure = true;
  String? _error;

  Future<void> _save() async {
    String? message;
    if ([_first, _last, _email, _password].any((c) => c.text.trim().isEmpty)) {
      message = 'Completa nombre, apellido, correo y contraseña.';
    } else if (!_email.text.contains('@')) {
      message = 'Escribe un correo válido.';
    } else if (_password.text.length < 6) {
      message = 'La contraseña debe tener al menos 6 caracteres.';
    } else if (_password.text != _confirm.text) {
      message = 'Las contraseñas no coinciden.';
    }
    if (message != null) {
      setState(() => _error = message);
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await context.read<ApiClient>().post('/register', {
        'user': {
          'first_name': _first.text.trim(),
          'last_name': _last.text.trim(),
          'email': _email.text.trim().toLowerCase(),
          'role': _role,
          'password': _password.text,
          'password_confirmation': _confirm.text,
        },
      });
      if (!mounted) return;
      showMessage(context, 'Usuario creado');
      Navigator.pop(context, true);
    } catch (error) {
      if (mounted) setState(() => _error = error.toString());
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => Padding(
        padding: EdgeInsets.fromLTRB(16, 16, 16, MediaQuery.of(context).viewInsets.bottom + 16),
        child: SingleChildScrollView(
          child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            Text('Nuevo usuario', style: Theme.of(context).textTheme.titleLarge),
            const Text('Tendrá acceso a tu empresa con el rol que elijas.'),
            const SizedBox(height: 12),
            if (_error != null) Text(_error!, style: TextStyle(color: Theme.of(context).colorScheme.error)),
            Row(children: [
              Expanded(child: TextField(controller: _first, decoration: const InputDecoration(labelText: 'Nombre *'))),
              const SizedBox(width: 8),
              Expanded(child: TextField(controller: _last, decoration: const InputDecoration(labelText: 'Apellido *'))),
            ]),
            const SizedBox(height: 12),
            TextField(controller: _email, keyboardType: TextInputType.emailAddress, decoration: const InputDecoration(labelText: 'Correo *')),
            const SizedBox(height: 12),
            TextField(
              controller: _password,
              obscureText: _obscure,
              decoration: InputDecoration(
                labelText: 'Contraseña *',
                suffixIcon: IconButton(icon: Icon(_obscure ? Icons.visibility_outlined : Icons.visibility_off_outlined), onPressed: () => setState(() => _obscure = !_obscure)),
              ),
            ),
            const SizedBox(height: 12),
            TextField(controller: _confirm, obscureText: _obscure, decoration: const InputDecoration(labelText: 'Confirmar contraseña *')),
            const SizedBox(height: 12),
            DropdownButtonFormField<String>(
              initialValue: _role,
              decoration: const InputDecoration(labelText: 'Rol'),
              items: [for (final r in assignableRoles) DropdownMenuItem(value: r, child: Text(roleLabels[r] ?? r))],
              onChanged: (v) => setState(() => _role = v ?? 'user'),
            ),
            const SizedBox(height: 16),
            FilledButton(onPressed: _busy ? null : _save, child: Text(_busy ? 'Creando…' : 'Crear usuario')),
          ]),
        ),
      );
}
