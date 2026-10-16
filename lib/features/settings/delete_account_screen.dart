import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/api_client.dart';
import '../../core/formatters.dart';
import '../../core/session.dart';
import '../../core/user_profile.dart';
import '../../widgets/async_states.dart';

/// Eliminación de la cuenta desde la app (requisito de Google Play). El
/// backend decide el alcance: solo el usuario o, si es el único
/// administrador, la empresa completa.
class DeleteAccountScreen extends StatefulWidget {
  const DeleteAccountScreen({super.key});

  @override
  State<DeleteAccountScreen> createState() => _DeleteAccountScreenState();
}

class _DeleteAccountScreenState extends State<DeleteAccountScreen> {
  final _confirmation = TextEditingController();
  Map<String, dynamic>? _preview;
  Object? _error;
  bool _deleting = false;

  @override
  void initState() {
    super.initState();
    _load();
    _confirmation.addListener(() => setState(() {}));
  }

  @override
  void dispose() {
    _confirmation.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() => _error = null);
    try {
      final data = asMap(await context.read<ApiClient>().get('/account_deletion'));
      if (mounted) setState(() => _preview = data);
    } catch (error) {
      if (mounted) setState(() => _error = error);
    }
  }

  String get _word => _preview?['confirmation']?.toString() ?? 'ELIMINAR';
  bool get _wholeAccount => _preview?['scope'] == 'account';

  Future<void> _delete() async {
    setState(() => _deleting = true);
    final session = context.read<SessionController>();
    try {
      final data = asMap(await context.read<ApiClient>().post('/account_deletion', {'confirmation': _confirmation.text.trim()}));
      await session.endSession(
        notice: data['deleted'] == 'account'
            ? 'Eliminamos tu empresa y todos sus usuarios.'
            : 'Eliminamos tu usuario. La empresa sigue activa para los demás.',
      );
    } catch (error) {
      if (mounted) {
        setState(() => _deleting = false);
        showError(context, error);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final preview = _preview;
    return Scaffold(
      appBar: AppBar(title: const Text('Eliminar mi cuenta')),
      body: _error != null
          ? ErrorView(error: _error!, onRetry: _load)
          : preview == null
              ? const LoadingView()
              : ListView(padding: const EdgeInsets.all(16), children: [
                  Card(
                    color: theme.colorScheme.errorContainer,
                    child: Padding(
                      padding: const EdgeInsets.all(16),
                      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        Row(children: [
                          Icon(Icons.warning_amber_rounded, color: theme.colorScheme.onErrorContainer),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              _wholeAccount ? 'Se eliminará ${preview['account_name']}' : 'Se eliminará tu usuario',
                              style: theme.textTheme.titleMedium?.copyWith(color: theme.colorScheme.onErrorContainer),
                            ),
                          ),
                        ]),
                        const SizedBox(height: 8),
                        Text(
                          _wholeAccount
                              ? 'Eres el único administrador, así que se elimina la empresa completa'
                                  '${(toNum(preview['other_users']) ?? 0) > 0 ? ' y sus otros ${preview['other_users']} usuario(s)' : ''}. '
                                  'Esta acción no se puede deshacer.'
                              : 'La empresa y los demás usuarios siguen activos. Esta acción no se puede deshacer.',
                          style: TextStyle(color: theme.colorScheme.onErrorContainer),
                        ),
                      ]),
                    ),
                  ),
                  const SizedBox(height: 12),
                  Card(
                    child: Padding(
                      padding: const EdgeInsets.all(16),
                      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        Text('Qué se elimina de inmediato', style: theme.textTheme.titleSmall),
                        const SizedBox(height: 4),
                        Text(_wholeAccount
                            ? 'Los nombres, correos, fotos y contraseñas de todos los usuarios, los datos de contacto y fiscales '
                                'de la empresa, las credenciales de facturación y el certificado de sello digital (CSD). '
                                'También se cancela la suscripción pagada con tarjeta.'
                            : 'Tu nombre, correo, foto de perfil, contraseña y sesiones abiertas.'),
                        const SizedBox(height: 12),
                        Text('Qué se conserva', style: theme.textTheme.titleSmall),
                        const SizedBox(height: 4),
                        const Text('Los registros de operación (inventario, compras, ventas y CFDI emitidos) quedan bloqueados y sin '
                            'acceso, sin tus datos personales, durante los 5 años que exige el Código Fiscal de la Federación.'),
                        if (preview['google_play_subscription'] == true) ...[
                          const SizedBox(height: 12),
                          Text('Tu plan se paga con Google Play', style: theme.textTheme.titleSmall),
                          const SizedBox(height: 4),
                          const Text('Cancélalo en Play Store → Pagos y suscripciones para que no se te vuelva a cobrar.'),
                        ],
                      ]),
                    ),
                  ),
                  const SizedBox(height: 16),
                  TextField(
                    controller: _confirmation,
                    enabled: !_deleting,
                    textCapitalization: TextCapitalization.characters,
                    autocorrect: false,
                    decoration: InputDecoration(labelText: 'Escribe $_word para confirmar', border: const OutlineInputBorder()),
                  ),
                  const SizedBox(height: 16),
                  FilledButton.icon(
                    style: FilledButton.styleFrom(backgroundColor: theme.colorScheme.error, foregroundColor: theme.colorScheme.onError),
                    onPressed: _deleting || _confirmation.text.trim().toUpperCase() != _word ? null : _delete,
                    icon: _deleting
                        ? const SizedBox.square(dimension: 18, child: CircularProgressIndicator(strokeWidth: 2))
                        : const Icon(Icons.delete_forever_outlined),
                    label: Text(_wholeAccount ? 'Eliminar la empresa definitivamente' : 'Eliminar mi usuario definitivamente'),
                  ),
                ]),
    );
  }
}
