import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../core/config.dart';
import '../../core/formatters.dart';
import '../../core/session.dart';
import '../../core/theme.dart';
import '../../widgets/app_shell.dart';
import '../../widgets/async_states.dart';

const _statusLabels = {
  'pending': 'Sin plan confirmado',
  'trial': 'En periodo de prueba',
  'active': 'Activa',
  'past_due': 'Pago atrasado',
  'suspended': 'Suspendida',
  'cancelled': 'Cancelada',
};

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  bool? _biometricsAvailable;

  @override
  void initState() {
    super.initState();
    context.read<SessionController>().biometricsAvailable().then((value) {
      if (mounted) setState(() => _biometricsAvailable = value);
    });
  }

  Future<void> _toggleBiometrics(bool value) async {
    try {
      await context.read<SessionController>().setBiometrics(value);
    } catch (error) {
      if (mounted) showError(context, error);
    }
  }

  Future<void> _confirmLogout() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Cerrar sesión'),
        content: const Text('Tendrás que volver a escribir tu correo y contraseña.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancelar')),
          FilledButton(onPressed: () => Navigator.pop(context, true), child: const Text('Cerrar sesión')),
        ],
      ),
    );
    if (ok == true && mounted) await context.read<SessionController>().logout();
  }

  @override
  Widget build(BuildContext context) {
    final session = context.watch<SessionController>();
    final themeController = context.watch<ThemeController>();
    final user = session.profile;
    final theme = Theme.of(context);
    final status = user?.accountStatus ?? '';

    return ModuleScaffold(
      title: 'Mi perfil y ajustes',
      body: RefreshIndicator(
        onRefresh: () async {
          try {
            await session.reloadProfile();
          } catch (error) {
            if (context.mounted) showError(context, error);
          }
        },
        child: ListView(padding: const EdgeInsets.all(16), children: [
          Card(
            child: ListTile(
              contentPadding: const EdgeInsets.all(16),
              leading: CircleAvatar(
                radius: 26,
                backgroundImage: (user?.profilePictureUrl?.isNotEmpty ?? false) ? NetworkImage(user!.profilePictureUrl!) : null,
                child: (user?.profilePictureUrl?.isNotEmpty ?? false) ? null : const Icon(Icons.person_outline),
              ),
              title: Text(user?.displayName ?? ''),
              subtitle: Text('${user?.email ?? ''}\nRol: ${user?.role ?? ''}'),
              isThreeLine: true,
            ),
          ),
          const SizedBox(height: 12),
          Card(
            child: Column(children: [
              ListTile(
                leading: const Icon(Icons.business_outlined),
                title: Text(user?.accountName ?? 'Empresa'),
                subtitle: Text([
                  _statusLabels[status] ?? status,
                  if (status == 'trial' && user?.trialEndsAt != null) 'termina el ${formatDate(user!.trialEndsAt!.toIso8601String())}',
                ].join(' · ')),
              ),
              ListTile(
                leading: const Icon(Icons.workspace_premium_outlined),
                title: const Text('Plan y pagos'),
                subtitle: const Text('Se administra desde la web'),
                trailing: const Icon(Icons.open_in_new, size: 18),
                onTap: () => launchUrl(Uri.parse('${AppConfig.webBaseUrl}/account-settings'),
                    mode: LaunchMode.externalApplication),
              ),
            ]),
          ),
          const SizedBox(height: 12),
          Card(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 14, 16, 8),
                child: Text('Apariencia', style: theme.textTheme.titleSmall),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                child: SegmentedButton<ThemeMode>(
                  segments: const [
                    ButtonSegment(value: ThemeMode.system, label: Text('Sistema'), icon: Icon(Icons.brightness_auto_outlined)),
                    ButtonSegment(value: ThemeMode.light, label: Text('Claro'), icon: Icon(Icons.light_mode_outlined)),
                    ButtonSegment(value: ThemeMode.dark, label: Text('Oscuro'), icon: Icon(Icons.dark_mode_outlined)),
                  ],
                  selected: {themeController.mode},
                  onSelectionChanged: (value) => themeController.setMode(value.first),
                ),
              ),
            ]),
          ),
          const SizedBox(height: 12),
          Card(
            child: SwitchListTile(
              secondary: const Icon(Icons.fingerprint),
              title: const Text('Entrar con huella o rostro'),
              subtitle: Text(_biometricsAvailable == false
                  ? 'Configura la biometría en los ajustes de Android para usarla.'
                  : 'Pide tu huella al abrir la app o tras ${AppShell.lockAfter.inMinutes} min en segundo plano.'),
              value: session.biometricEnabled,
              onChanged: _biometricsAvailable == false ? null : _toggleBiometrics,
            ),
          ),
          const SizedBox(height: 12),
          Card(
            child: ListTile(
              leading: Icon(Icons.logout, color: theme.colorScheme.error),
              title: Text('Cerrar sesión', style: TextStyle(color: theme.colorScheme.error)),
              onTap: _confirmLogout,
            ),
          ),
          const SizedBox(height: 24),
        ]),
      ),
    );
  }
}
