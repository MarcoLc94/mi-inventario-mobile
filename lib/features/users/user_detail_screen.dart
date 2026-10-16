import 'dart:io';

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:image_picker/image_picker.dart';
import 'package:provider/provider.dart';

import '../../core/api_client.dart';
import '../../core/formatters.dart';
import '../../core/session.dart';
import '../../core/user_profile.dart';
import '../../widgets/async_states.dart';
import '../../widgets/form_fields.dart';
import 'users_screen.dart';

/// Detalle y edición de un usuario. El admin edita datos, rol y permisos
/// básicos; cualquiera puede cambiar su propia foto y contraseña.
class UserDetailScreen extends StatefulWidget {
  const UserDetailScreen({super.key, required this.id});
  final String id;

  @override
  State<UserDetailScreen> createState() => _UserDetailScreenState();
}

class _UserDetailScreenState extends State<UserDetailScreen> {
  Map<String, dynamic>? _user;
  Object? _error;
  bool _busy = false;
  bool _changed = false;
  final _first = TextEditingController();
  final _last = TextEditingController();
  final _email = TextEditingController();
  final _password = TextEditingController();
  final _confirm = TextEditingController();
  String _role = 'user';
  bool _approveMovements = false;
  bool _editProducts = false;
  XFile? _photo;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final u = asMap(await context.read<ApiClient>().get('/users/${widget.id}'));
      if (!mounted) return;
      setState(() {
        _user = u;
        _first.text = u['first_name']?.toString() ?? '';
        _last.text = u['last_name']?.toString() ?? '';
        _email.text = u['email']?.toString() ?? '';
        _role = u['role']?.toString() ?? 'user';
        _approveMovements = u['can_approve_movements'] == true;
        _editProducts = u['can_edit_products'] == true;
      });
    } catch (error) {
      if (mounted) setState(() => _error = error);
    }
  }

  Future<void> _pickPhoto() async {
    final file = await ImagePicker().pickImage(source: ImageSource.gallery, imageQuality: 85, maxWidth: 800);
    if (file != null) setState(() => _photo = file);
  }

  Future<void> _save(bool isAdmin) async {
    if (_password.text.isNotEmpty && (_password.text.length < 6 || _password.text != _confirm.text)) {
      showMessage(context, _password.text != _confirm.text ? 'Las contraseñas no coinciden.' : 'La contraseña debe tener al menos 6 caracteres.');
      return;
    }
    setState(() => _busy = true);
    final fields = <MapEntry<String, String>>[
      if (isAdmin) ...[
        MapEntry('user[first_name]', _first.text.trim()),
        MapEntry('user[last_name]', _last.text.trim()),
        MapEntry('user[email]', _email.text.trim().toLowerCase()),
        MapEntry('user[role]', _role),
        MapEntry('user[can_approve_movements]', '$_approveMovements'),
        MapEntry('user[can_edit_products]', '$_editProducts'),
      ],
      if (_password.text.isNotEmpty) ...[
        MapEntry('user[password]', _password.text),
        MapEntry('user[password_confirmation]', _confirm.text),
      ],
    ];
    try {
      final session = context.read<SessionController>();
      await context.read<ApiClient>().multipart('PUT', '/users/${widget.id}',
          fields: fields, files: [if (_photo != null) MapEntry('user[profile_picture]', _photo!.path)]);
      _changed = true;
      _password.clear();
      _confirm.clear();
      _photo = null;
      if (session.profile?.id.toString() == widget.id) await session.reloadProfile().catchError((_) {});
      if (mounted) showMessage(context, 'Usuario actualizado');
      await _load();
    } catch (error) {
      if (mounted) showError(context, error);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _delete() async {
    if (!await confirm(context, title: 'Eliminar usuario', message: '¿Eliminar a ${_first.text} ${_last.text}? Ya no podrá entrar.', action: 'Eliminar', destructive: true) ||
        !mounted) {
      return;
    }
    try {
      await context.read<ApiClient>().delete('/users/${widget.id}');
      if (mounted) context.pop(true);
    } catch (error) {
      if (mounted) showError(context, error);
    }
  }

  @override
  Widget build(BuildContext context) {
    final me = context.watch<SessionController>().profile;
    final isAdmin = me?.isAdmin ?? false;
    final isSelf = me?.id.toString() == widget.id;
    final u = _user;
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) Navigator.of(context).pop(_changed);
      },
      child: Scaffold(
        appBar: AppBar(
          title: const Text('Usuario'),
          actions: [
            if (isAdmin && !isSelf && u != null)
              PopupMenuButton<String>(onSelected: (_) => _delete(), itemBuilder: (_) => const [PopupMenuItem(value: 'delete', child: Text('Eliminar usuario'))]),
          ],
        ),
        body: u == null
            ? (_error != null ? ErrorView(error: _error!, onRetry: _load) : const LoadingView())
            : ListView(padding: const EdgeInsets.all(16), children: [
                Center(
                  child: Stack(children: [
                    CircleAvatar(
                      radius: 44,
                      backgroundImage: _photo != null
                          ? FileImage(File(_photo!.path))
                          : (u['profile_picture_url']?.toString().isNotEmpty ?? false)
                              ? NetworkImage(u['profile_picture_url'].toString()) as ImageProvider
                              : null,
                      child: _photo == null && !(u['profile_picture_url']?.toString().isNotEmpty ?? false) ? const Icon(Icons.person, size: 40) : null,
                    ),
                    if (isAdmin || isSelf)
                      Positioned(right: 0, bottom: 0, child: IconButton.filledTonal(tooltip: 'Cambiar foto', onPressed: _pickPhoto, icon: const Icon(Icons.photo_camera_outlined))),
                  ]),
                ),
                const SizedBox(height: 16),
                SectionCard(title: 'Actividad', children: [
                  InfoRow('Último inicio de sesión', formatDateTime(u['last_login_at'])),
                  InfoRow('Última actividad', u['last_seen_at'] == null ? null : formatDateTime(u['last_seen_at'])),
                ]),
                const SizedBox(height: 12),
                TextField(controller: _first, enabled: isAdmin, decoration: const InputDecoration(labelText: 'Nombre')),
                const SizedBox(height: 12),
                TextField(controller: _last, enabled: isAdmin, decoration: const InputDecoration(labelText: 'Apellido')),
                const SizedBox(height: 12),
                TextField(controller: _email, enabled: isAdmin, keyboardType: TextInputType.emailAddress, decoration: const InputDecoration(labelText: 'Correo')),
                const SizedBox(height: 12),
                DropdownButtonFormField<String>(
                  initialValue: roleLabels.containsKey(_role) ? _role : null,
                  decoration: const InputDecoration(labelText: 'Rol'),
                  items: [for (final r in {...assignableRoles, _role}) DropdownMenuItem(value: r, child: Text(roleLabels[r] ?? r))],
                  onChanged: isAdmin && !isSelf ? (v) => setState(() => _role = v ?? _role) : null,
                ),
                if (isAdmin) ...[
                  SwitchListTile(contentPadding: EdgeInsets.zero, title: const Text('Puede aprobar movimientos'), value: _approveMovements, onChanged: (v) => setState(() => _approveMovements = v)),
                  SwitchListTile(contentPadding: EdgeInsets.zero, title: const Text('Puede editar productos'), value: _editProducts, onChanged: (v) => setState(() => _editProducts = v)),
                ],
                if (isAdmin || isSelf) ...[
                  const SizedBox(height: 8),
                  Text('Cambiar contraseña', style: Theme.of(context).textTheme.titleSmall),
                  const SizedBox(height: 8),
                  TextField(controller: _password, obscureText: true, decoration: const InputDecoration(labelText: 'Nueva contraseña')),
                  const SizedBox(height: 12),
                  TextField(controller: _confirm, obscureText: true, decoration: const InputDecoration(labelText: 'Confirmar contraseña')),
                  const SizedBox(height: 16),
                  FilledButton(onPressed: _busy ? null : () => _save(isAdmin), child: Text(_busy ? 'Guardando…' : 'Guardar cambios')),
                ],
                const SizedBox(height: 24),
              ]),
      ),
    );
  }
}
