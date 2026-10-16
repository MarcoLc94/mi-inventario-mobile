import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:image_picker/image_picker.dart';
import 'package:provider/provider.dart';

import '../../core/api_client.dart';
import '../../core/session.dart';
import '../../core/user_profile.dart';
import '../../widgets/app_shell.dart';
import '../../widgets/async_states.dart';
import '../../widgets/form_fields.dart';

/// Ajustes de cuenta: datos de la empresa (los que salen en documentos y
/// tickets), logo, plan y estado de los módulos. Los módulos adicionales se
/// contratan en la web; en la app solo se muestra su estado.
class AccountSettingsScreen extends StatefulWidget {
  const AccountSettingsScreen({super.key});

  @override
  State<AccountSettingsScreen> createState() => _AccountSettingsScreenState();
}

class _AccountSettingsScreenState extends State<AccountSettingsScreen> {
  Map<String, dynamic>? _account;
  Map<String, dynamic>? _billing;
  Object? _error;
  bool _saving = false;
  XFile? _logo;
  final _c = {
    for (final key in ['legal_name', 'tax_id', 'tagline', 'address', 'phone', 'whatsapp_phone', 'email', 'default_delivery_place']) key: TextEditingController(),
  };
  num _iva = 0.16;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    for (final c in _c.values) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _load() async {
    try {
      final api = context.read<ApiClient>();
      final results = await Future.wait([api.get('/account'), api.get('/billing')]);
      final account = asMap(results[0]);
      if (!mounted) return;
      setState(() {
        _account = account;
        _billing = asMap(results[1]);
        for (final e in _c.entries) {
          e.value.text = account[e.key]?.toString() ?? '';
        }
        _iva = const [0, 0.08, 0.16].contains(num.tryParse('${account['default_iva_rate']}')) ? num.parse('${account['default_iva_rate']}') : 0.16;
      });
    } catch (error) {
      if (mounted) setState(() => _error = error);
    }
  }

  Future<void> _save() async {
    setState(() => _saving = true);
    final values = {for (final e in _c.entries) e.key: e.value.text.trim(), 'default_iva_rate': '$_iva'};
    try {
      final api = context.read<ApiClient>();
      final updated = _logo == null
          ? await api.put('/account', {'account': values})
          : await api.multipart('PUT', '/account',
              fields: [for (final e in values.entries) MapEntry('account[${e.key}]', e.value)], files: [MapEntry('account[logo]', _logo!.path)]);
      if (!mounted) return;
      setState(() {
        _account = asMap(updated);
        _logo = null;
      });
      showMessage(context, 'Datos de la empresa guardados');
    } catch (error) {
      if (mounted) showError(context, error);
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Widget _addon(String label, Map<String, dynamic> addon) {
    final active = addon['active'] == true;
    return ListTile(
      leading: Icon(active ? Icons.check_circle_outline : Icons.lock_outline, color: active ? Colors.green.shade700 : null),
      title: Text(label),
      subtitle: Text(active ? 'Activo' : 'No contratado'),
    );
  }

  @override
  Widget build(BuildContext context) {
    final a = _account;
    final canManage = context.watch<SessionController>().profile?.isAdmin ?? false;
    Widget body;
    if (a == null) {
      body = _error != null ? ErrorView(error: _error!, onRetry: _load) : const LoadingView();
    } else {
      final theme = Theme.of(context);
      body = ListView(padding: const EdgeInsets.all(16), children: [
        Card(
          child: ListTile(
            leading: const Icon(Icons.workspace_premium_outlined),
            title: const Text('Plan y suscripción'),
            subtitle: Text(_billing?['plan'] == 'free'
                ? 'Plan gratuito'
                : a['status']?.toString() == 'active'
                    ? 'Activa'
                    : a['status']?.toString() ?? ''),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => context.push('/billing'),
          ),
        ),
        const SizedBox(height: 12),
        SectionCard(title: 'Módulos', children: [
          const ListTile(leading: Icon(Icons.check_circle_outline), title: Text('Inventario'), subtitle: Text('Incluido en tu cuenta')),
          _addon('Facturación', asMap(_billing?['invoicing'])),
          _addon('Punto de venta / Caja', asMap(_billing?['pos'])),
        ]),
        const SizedBox(height: 16),
        Text('Empresa', style: theme.textTheme.titleMedium),
        Text('Estos datos aparecen en tus documentos y tickets.', style: theme.textTheme.bodySmall),
        const SizedBox(height: 12),
        Row(children: [
          CircleAvatar(
            radius: 32,
            backgroundImage: (a['logo_url']?.toString().isNotEmpty ?? false) ? NetworkImage(a['logo_url'].toString()) : null,
            child: (a['logo_url']?.toString().isNotEmpty ?? false) ? null : const Icon(Icons.business),
          ),
          const SizedBox(width: 12),
          Expanded(child: Text(a['name']?.toString() ?? '', style: theme.textTheme.titleMedium)),
          if (canManage)
            TextButton(
              onPressed: () async {
                final file = await ImagePicker().pickImage(source: ImageSource.gallery, maxWidth: 1000, imageQuality: 90);
                if (file != null) setState(() => _logo = file);
              },
              child: Text(_logo == null ? 'Cambiar logo' : 'Logo listo para guardar'),
            ),
        ]),
        const SizedBox(height: 12),
        for (final (key, label, keyboard) in [
          ('legal_name', 'Razón social', TextInputType.text),
          ('tax_id', 'RFC', TextInputType.text),
          ('tagline', 'Lema o descripción corta', TextInputType.text),
          ('address', 'Dirección', TextInputType.streetAddress),
          ('phone', 'Teléfono', TextInputType.phone),
          ('whatsapp_phone', 'WhatsApp', TextInputType.phone),
          ('email', 'Correo', TextInputType.emailAddress),
          ('default_delivery_place', 'Lugar de entrega predeterminado', TextInputType.text),
        ])
          Padding(
            padding: const EdgeInsets.only(bottom: 12),
            child: TextField(controller: _c[key], enabled: canManage, keyboardType: keyboard, decoration: InputDecoration(labelText: label)),
          ),
        DropdownButtonFormField<num>(
          initialValue: _iva,
          decoration: const InputDecoration(labelText: 'IVA predeterminado'),
          items: const [DropdownMenuItem(value: 0.16, child: Text('16 %')), DropdownMenuItem(value: 0.08, child: Text('8 % (frontera)')), DropdownMenuItem(value: 0, child: Text('0 %'))],
          onChanged: canManage ? (v) => setState(() => _iva = v ?? 0.16) : null,
        ),
        const SizedBox(height: 16),
        if (canManage) FilledButton(onPressed: _saving ? null : _save, child: Text(_saving ? 'Guardando…' : 'Guardar cambios')),
        const SizedBox(height: 24),
      ]);
    }
    return ModuleScaffold(title: 'Ajustes de cuenta', body: body);
  }
}
