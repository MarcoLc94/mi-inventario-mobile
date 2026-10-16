import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../core/config.dart';
import '../../widgets/app_shell.dart';
import '../../widgets/async_states.dart';

/// Módulo que todavía no está en la app: se puede abrir en la web.
class ModulePlaceholder extends StatelessWidget {
  const ModulePlaceholder({super.key, required this.title, required this.path});
  final String title;
  final String path;

  @override
  Widget build(BuildContext context) => ModuleScaffold(
        title: title,
        body: MessageView(
          icon: Icons.construction_outlined,
          title: '$title llega pronto a la app',
          message: 'Mientras tanto puedes usarlo desde la web con la misma cuenta.',
          action: FilledButton.icon(
            onPressed: () => launchUrl(Uri.parse('${AppConfig.webBaseUrl}$path'), mode: LaunchMode.externalApplication),
            icon: const Icon(Icons.open_in_new),
            label: const Text('Abrir en la web'),
          ),
        ),
      );
}
