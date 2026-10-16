import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/api_client.dart';
import '../../core/user_profile.dart';

/// Alta y edición de proveedores (mismos campos que la web).
class SupplierFormScreen extends StatefulWidget {
  const SupplierFormScreen({super.key, this.supplier});
  final Map<String, dynamic>? supplier;

  @override
  State<SupplierFormScreen> createState() => _SupplierFormScreenState();
}

class _SupplierFormScreenState extends State<SupplierFormScreen> {
  late final Map<String, dynamic> _s = widget.supplier ?? const {};
  late final _c = {
    for (final key in ['name', 'contact_name', 'tax_id', 'email', 'phone', 'address', 'city', 'state', 'postal_code', 'notes'])
      key: TextEditingController(text: _s[key]?.toString() ?? ''),
    'country': TextEditingController(text: _s['country']?.toString() ?? 'México'),
    'lead_time_days': TextEditingController(text: _s['lead_time_days']?.toString() ?? '7'),
    'minimum_order_quantity': TextEditingController(text: _s['minimum_order_quantity']?.toString() ?? '0'),
    'credit_limit': TextEditingController(text: _s['credit_limit']?.toString() ?? '0'),
    'base_folio': TextEditingController(text: _s['base_folio']?.toString() ?? '0'),
  };
  late String _currency = _s['currency']?.toString() ?? 'MXN';
  late String _status = _s['status']?.toString() ?? 'active';
  bool _saving = false;
  String? _error;

  bool get _editing => widget.supplier != null;

  @override
  void dispose() {
    for (final c in _c.values) {
      c.dispose();
    }
    super.dispose();
  }

  String _t(String key) => _c[key]!.text.trim();

  Future<void> _save() async {
    if (_t('name').isEmpty || _t('contact_name').isEmpty || _t('tax_id').isEmpty) {
      setState(() => _error = 'Nombre, razón social y RFC son obligatorios.');
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
      for (final key in ['name', 'contact_name', 'phone', 'address', 'city', 'state', 'postal_code', 'country', 'notes']) key: _t(key),
      'tax_id': _t('tax_id').replaceAll(RegExp(r'\s'), '').toUpperCase(),
      'email': _t('email').toLowerCase(),
      'currency': _currency,
      'status': _status,
      'lead_time_days': int.tryParse(_t('lead_time_days')) ?? 7,
      'minimum_order_quantity': num.tryParse(_t('minimum_order_quantity')) ?? 0,
      'credit_limit': num.tryParse(_t('credit_limit')) ?? 0,
      'base_folio': int.tryParse(_t('base_folio')) ?? 0,
    };
    try {
      final api = context.read<ApiClient>();
      final result = _editing ? await api.put('/suppliers/${_s['id']}', {'supplier': payload}) : await api.post('/suppliers', {'supplier': payload});
      if (mounted) Navigator.pop(context, asMap(result));
    } catch (error) {
      if (mounted) setState(() => _error = error.toString());
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Widget _field(String key, String label, {TextInputType? keyboard, String? hint, int lines = 1}) => Padding(
        padding: const EdgeInsets.only(bottom: 12),
        child: TextField(controller: _c[key], keyboardType: keyboard, maxLines: lines, decoration: InputDecoration(labelText: label, hintText: hint)),
      );

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(title: Text(_editing ? 'Editar proveedor' : 'Nuevo proveedor')),
      body: ListView(padding: const EdgeInsets.fromLTRB(16, 16, 16, 120), children: [
        if (_error != null) Padding(padding: const EdgeInsets.only(bottom: 12), child: Text(_error!, style: TextStyle(color: theme.colorScheme.error))),
        Text('Datos básicos', style: theme.textTheme.titleMedium),
        const SizedBox(height: 8),
        _field('name', 'Nombre del proveedor *', hint: 'Ej. Distribuidora del Norte'),
        _field('contact_name', 'Razón social *', hint: 'Nombre fiscal o de la persona'),
        _field('tax_id', 'RFC *'),
        Text('Contacto', style: theme.textTheme.titleMedium),
        const SizedBox(height: 8),
        _field('email', 'Correo electrónico', keyboard: TextInputType.emailAddress),
        _field('phone', 'Teléfono', keyboard: TextInputType.phone),
        Text('Dirección', style: theme.textTheme.titleMedium),
        const SizedBox(height: 8),
        _field('address', 'Calle, número y colonia'),
        _field('city', 'Ciudad o municipio'),
        _field('state', 'Estado'),
        _field('postal_code', 'Código postal', keyboard: TextInputType.number),
        _field('country', 'País'),
        Text('Condiciones de compra', style: theme.textTheme.titleMedium),
        const SizedBox(height: 8),
        DropdownButtonFormField<String>(
          initialValue: _currency,
          decoration: const InputDecoration(labelText: 'Moneda'),
          items: const [
            DropdownMenuItem(value: 'MXN', child: Text('MXN · Peso mexicano')),
            DropdownMenuItem(value: 'USD', child: Text('USD · Dólar estadounidense')),
            DropdownMenuItem(value: 'EUR', child: Text('EUR · Euro')),
          ],
          onChanged: (v) => setState(() => _currency = v ?? 'MXN'),
        ),
        const SizedBox(height: 12),
        DropdownButtonFormField<String>(
          initialValue: _status,
          decoration: const InputDecoration(labelText: 'Estado del proveedor'),
          items: const [
            DropdownMenuItem(value: 'active', child: Text('Activo')),
            DropdownMenuItem(value: 'suspended', child: Text('Suspendido')),
            DropdownMenuItem(value: 'discontinued', child: Text('Descontinuado')),
          ],
          onChanged: (v) => setState(() => _status = v ?? 'active'),
        ),
        const SizedBox(height: 12),
        _field('lead_time_days', 'Tiempo de entrega (días)', keyboard: TextInputType.number),
        _field('minimum_order_quantity', 'Cantidad mínima de compra', keyboard: const TextInputType.numberWithOptions(decimal: true)),
        _field('credit_limit', 'Límite de crédito', keyboard: const TextInputType.numberWithOptions(decimal: true)),
        _field('base_folio', 'Folio inicial de compras', keyboard: TextInputType.number),
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
