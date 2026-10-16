import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/api_client.dart';
import '../../core/user_profile.dart';

/// Alta y edición de clientes (mismos campos que la web).
class ClientFormScreen extends StatefulWidget {
  const ClientFormScreen({super.key, this.client});
  final Map<String, dynamic>? client;

  @override
  State<ClientFormScreen> createState() => _ClientFormScreenState();
}

class _ClientFormScreenState extends State<ClientFormScreen> {
  late final Map<String, dynamic> _c = widget.client ?? const {};
  late final _f = {
    for (final key in ['name', 'email', 'phone', 'legal_name', 'tax_id', 'address', 'city', 'state', 'postal_code', 'notes'])
      key: TextEditingController(text: _c[key]?.toString() ?? ''),
    'country': TextEditingController(text: _c['country']?.toString() ?? 'México'),
    'credit_limit': TextEditingController(text: _c['credit_limit']?.toString() ?? '0'),
  };
  late String _status = _c['status']?.toString() ?? 'active';
  bool _saving = false;
  String? _error;

  bool get _editing => widget.client != null;

  @override
  void dispose() {
    for (final c in _f.values) {
      c.dispose();
    }
    super.dispose();
  }

  String _t(String key) => _f[key]!.text.trim();

  Future<void> _save() async {
    if (_t('name').isEmpty) {
      setState(() => _error = 'Escribe el nombre del cliente.');
      return;
    }
    if (_t('email').isNotEmpty && !_t('email').contains('@')) {
      setState(() => _error = 'Escribe un correo válido.');
      return;
    }
    setState(() {
      _saving = true;
      _error = null;
    });
    final payload = {
      for (final key in ['name', 'phone', 'legal_name', 'address', 'city', 'state', 'postal_code', 'country', 'notes']) key: _t(key),
      'email': _t('email').toLowerCase(),
      'tax_id': _t('tax_id').replaceAll(RegExp(r'\s'), '').toUpperCase(),
      'credit_limit': num.tryParse(_t('credit_limit')) ?? 0,
      'status': _status,
    };
    try {
      final api = context.read<ApiClient>();
      final result = _editing ? await api.put('/clients/${_c['id']}', {'client': payload}) : await api.post('/clients', {'client': payload});
      if (mounted) Navigator.pop(context, asMap(result));
    } catch (error) {
      if (mounted) setState(() => _error = error.toString());
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Widget _field(String key, String label, {TextInputType? keyboard, int lines = 1, String? hint}) => Padding(
        padding: const EdgeInsets.only(bottom: 12),
        child: TextField(controller: _f[key], keyboardType: keyboard, maxLines: lines, decoration: InputDecoration(labelText: label, hintText: hint)),
      );

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(title: Text(_editing ? 'Editar cliente' : 'Nuevo cliente')),
      body: ListView(padding: const EdgeInsets.fromLTRB(16, 16, 16, 120), children: [
        if (_error != null) Padding(padding: const EdgeInsets.only(bottom: 12), child: Text(_error!, style: TextStyle(color: theme.colorScheme.error))),
        _field('name', 'Nombre *'),
        _field('email', 'Correo electrónico', keyboard: TextInputType.emailAddress),
        _field('phone', 'Teléfono', keyboard: TextInputType.phone),
        Text('Datos fiscales', style: theme.textTheme.titleMedium),
        Text('Puedes completarlos después, antes de facturarle.', style: theme.textTheme.bodySmall),
        const SizedBox(height: 8),
        _field('legal_name', 'Razón social', hint: 'Nombre fiscal del cliente'),
        _field('tax_id', 'RFC'),
        _field('postal_code', 'Código postal', keyboard: TextInputType.number),
        Text('Dirección', style: theme.textTheme.titleMedium),
        const SizedBox(height: 8),
        _field('address', 'Calle, número y colonia'),
        _field('city', 'Ciudad o municipio'),
        _field('state', 'Estado'),
        _field('country', 'País'),
        DropdownButtonFormField<String>(
          initialValue: _status,
          decoration: const InputDecoration(labelText: 'Estado del cliente'),
          items: const [
            DropdownMenuItem(value: 'active', child: Text('Activo')),
            DropdownMenuItem(value: 'inactive', child: Text('Inactivo')),
            DropdownMenuItem(value: 'suspended', child: Text('Suspendido')),
          ],
          onChanged: (v) => setState(() => _status = v ?? 'active'),
        ),
        const SizedBox(height: 12),
        _field('credit_limit', 'Límite de crédito', keyboard: const TextInputType.numberWithOptions(decimal: true)),
        _field('notes', 'Comentarios', lines: 3),
      ]),
      bottomNavigationBar: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: FilledButton(onPressed: _saving ? null : _save, child: Text(_saving ? 'Guardando…' : 'Guardar')),
        ),
      ),
    );
  }
}
