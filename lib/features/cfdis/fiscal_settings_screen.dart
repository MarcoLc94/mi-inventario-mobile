import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/api_client.dart';
import '../../core/formatters.dart';
import '../../core/user_profile.dart';
import '../../widgets/app_shell.dart';
import '../../widgets/async_states.dart';
import '../../widgets/form_fields.dart';
import 'cfdi_catalogs.dart';

/// CFDIs > Configuración fiscal: datos del emisor y su Certificado de Sello
/// Digital (CSD), que el backend registra en Facturama.
class FiscalSettingsScreen extends StatefulWidget {
  const FiscalSettingsScreen({super.key});

  @override
  State<FiscalSettingsScreen> createState() => _FiscalSettingsScreenState();
}

class _FiscalSettingsScreenState extends State<FiscalSettingsScreen> {
  Map<String, dynamic>? _profile;
  Object? _error;
  final _legalName = TextEditingController();
  final _taxId = TextEditingController();
  final _zip = TextEditingController();
  final _series = TextEditingController();
  String? _regime;
  bool _saving = false;
  bool _uploading = false;
  PlatformFile? _certificate;
  PlatformFile? _privateKey;
  final _password = TextEditingController();

  ApiClient get _api => context.read<ApiClient>();

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    for (final c in [_legalName, _taxId, _zip, _series, _password]) {
      c.dispose();
    }
    super.dispose();
  }

  void _apply(Map<String, dynamic> data) {
    setState(() {
      _profile = data;
      _legalName.text = data['legal_name']?.toString() ?? '';
      _taxId.text = data['tax_id']?.toString() ?? '';
      _zip.text = data['tax_zip_code']?.toString() ?? '';
      _series.text = data['invoice_series']?.toString().isNotEmpty == true ? data['invoice_series'].toString() : 'A';
      _regime = fiscalRegimes.containsKey(data['fiscal_regime']) ? data['fiscal_regime'].toString() : null;
    });
  }

  Future<void> _load() async {
    try {
      _apply(asMap(await _api.get('/fiscal_profile')));
    } catch (error) {
      if (mounted) setState(() => _error = error);
    }
  }

  Future<void> _saveIssuer() async {
    setState(() => _saving = true);
    try {
      _apply(asMap(await _api.patch('/fiscal_profile', {
        'fiscal_profile': {
          'legal_name': _legalName.text.trim(),
          'tax_id': _taxId.text.trim().toUpperCase(),
          'fiscal_regime': _regime ?? '',
          'tax_zip_code': _zip.text.trim(),
          'invoice_series': _series.text.trim(),
        },
      })));
      if (mounted) showMessage(context, 'Datos fiscales guardados');
    } catch (error) {
      if (mounted) showError(context, error);
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _pick(bool certificate) async {
    final files = await FilePicker.pickFiles(type: FileType.any);
    final file = files.firstOrNull;
    if (file == null || file.path == null) return;
    final expected = certificate ? '.cer' : '.key';
    if (!file.name.toLowerCase().endsWith(expected)) {
      if (mounted) showMessage(context, 'Elige el archivo $expected de tu sello digital.');
      return;
    }
    setState(() => certificate ? _certificate = file : _privateKey = file);
  }

  Future<void> _upload() async {
    if (_certificate == null || _privateKey == null || _password.text.isEmpty) {
      showMessage(context, 'Selecciona el .cer, el .key y escribe la contraseña de la llave.');
      return;
    }
    setState(() => _uploading = true);
    try {
      _apply(asMap(await _api.multipart('POST', '/fiscal_profile/csd',
          fields: [MapEntry('password', _password.text)],
          files: [MapEntry('certificate', _certificate!.path!), MapEntry('private_key', _privateKey!.path!)])));
      if (!mounted) return;
      showMessage(context, 'Sello digital registrado. Ya puedes timbrar facturas.');
      setState(() {
        _certificate = null;
        _privateKey = null;
      });
    } catch (error) {
      if (mounted) showError(context, error);
    } finally {
      _password.clear();
      if (mounted) setState(() => _uploading = false);
    }
  }

  Future<void> _removeCsd() async {
    if (!await confirm(context, title: 'Eliminar sello digital', message: 'Ya no podrás timbrar hasta subir otro CSD.', action: 'Eliminar', destructive: true) || !mounted) return;
    setState(() => _uploading = true);
    try {
      _apply(asMap(await _api.delete('/fiscal_profile/csd')));
      if (mounted) showMessage(context, 'Sello digital eliminado');
    } catch (error) {
      if (mounted) showError(context, error);
    } finally {
      if (mounted) setState(() => _uploading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final p = _profile;
    final theme = Theme.of(context);
    Widget body;
    if (p == null) {
      body = _error != null ? ErrorView(error: _error!, onRetry: _load) : const LoadingView(label: 'Cargando configuración fiscal…');
    } else {
      final csd = asMap(p['csd']);
      final missing = [...(p['missing'] as List? ?? const []).map((e) => e.toString()), if (csd['active'] != true) 'Sello digital (CSD)'];
      final validUntil = parseDate(csd['valid_until']);
      final remaining = validUntil?.difference(DateTime.now()).inDays;
      body = ListView(padding: const EdgeInsets.all(16), children: [
        const CfdiSandboxBanner(),
        if (p['service_configured'] != true)
          Card(
            color: theme.colorScheme.errorContainer,
            child: const Padding(padding: EdgeInsets.all(12), child: Text('El servicio de timbrado todavía no está disponible. Puedes capturar tus datos; contacta a soporte para activarlo.')),
          ),
        Card(
          color: missing.isEmpty ? Colors.green.shade50 : theme.colorScheme.tertiaryContainer,
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Text(missing.isEmpty ? 'Todo listo: ya puedes timbrar facturas.' : 'Para timbrar falta: ${missing.join(', ')}.',
                style: TextStyle(color: missing.isEmpty ? Colors.green.shade900 : null)),
          ),
        ),
        const SizedBox(height: 12),
        Text('Datos del emisor', style: theme.textTheme.titleMedium),
        const SizedBox(height: 8),
        TextField(controller: _legalName, decoration: const InputDecoration(labelText: 'Razón social (como aparece en tu constancia)')),
        const SizedBox(height: 12),
        TextField(controller: _taxId, textCapitalization: TextCapitalization.characters, decoration: const InputDecoration(labelText: 'RFC')),
        const SizedBox(height: 12),
        DropdownButtonFormField<String>(
          initialValue: _regime,
          isExpanded: true,
          decoration: const InputDecoration(labelText: 'Régimen fiscal'),
          items: [for (final e in fiscalRegimes.entries) DropdownMenuItem(value: e.key, child: Text(e.value, overflow: TextOverflow.ellipsis))],
          onChanged: (v) => setState(() => _regime = v),
        ),
        const SizedBox(height: 12),
        Row(children: [
          Expanded(child: TextField(controller: _zip, keyboardType: TextInputType.number, maxLength: 5, decoration: const InputDecoration(labelText: 'Código postal fiscal'))),
          const SizedBox(width: 12),
          Expanded(child: TextField(controller: _series, maxLength: 10, decoration: const InputDecoration(labelText: 'Serie de facturas'))),
        ]),
        FilledButton(onPressed: _saving ? null : _saveIssuer, child: Text(_saving ? 'Guardando…' : 'Guardar datos fiscales')),
        const SizedBox(height: 24),
        Text('Sello digital (CSD)', style: theme.textTheme.titleMedium),
        const SizedBox(height: 8),
        if (csd['uploaded_at'] != null)
          SectionCard(title: csd['active'] == true ? 'Sello registrado' : 'Sello inactivo', children: [
            InfoRow('RFC', csd['rfc']?.toString()),
            InfoRow('No. de serie', csd['serial_number']?.toString()),
            InfoRow('Vigencia', '${formatDate(csd['valid_from'])} – ${formatDate(csd['valid_until'])}'),
            if (remaining != null && remaining <= 30)
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: Text(remaining < 0 ? 'El sello está vencido. Tramita uno nuevo en el SAT.' : 'El sello vence en $remaining días.',
                    style: TextStyle(color: theme.colorScheme.error)),
              ),
            Padding(
              padding: const EdgeInsets.all(16),
              child: OutlinedButton(
                style: OutlinedButton.styleFrom(foregroundColor: theme.colorScheme.error),
                onPressed: _uploading ? null : _removeCsd,
                child: const Text('Eliminar sello'),
              ),
            ),
          ])
        else ...[
          const Text('Sube los archivos .cer y .key de tu Certificado de Sello Digital y la contraseña de la llave privada.'),
          const SizedBox(height: 12),
          OutlinedButton.icon(onPressed: () => _pick(true), icon: const Icon(Icons.attach_file), label: Text(_certificate?.name ?? 'Elegir certificado (.cer)')),
          const SizedBox(height: 8),
          OutlinedButton.icon(onPressed: () => _pick(false), icon: const Icon(Icons.key_outlined), label: Text(_privateKey?.name ?? 'Elegir llave privada (.key)')),
          const SizedBox(height: 8),
          TextField(controller: _password, obscureText: true, decoration: const InputDecoration(labelText: 'Contraseña de la llave privada')),
          const SizedBox(height: 12),
          FilledButton(onPressed: _uploading ? null : _upload, child: Text(_uploading ? 'Registrando…' : 'Registrar sello digital')),
        ],
        const SizedBox(height: 24),
      ]);
    }
    return ModuleScaffold(title: 'Configuración fiscal', body: body);
  }
}
