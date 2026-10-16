import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../../core/session.dart';
import '../../widgets/app_shell.dart';
import 'tutorials_data.dart';

/// Tutoriales: los mismos recorridos de Boxy que en la web, paso a paso, con
/// un botón para abrir la pantalla de cada paso.
class TutorialsScreen extends StatelessWidget {
  const TutorialsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final user = context.watch<SessionController>().profile;
    final theme = Theme.of(context);
    return ModuleScaffold(
      title: 'Tutoriales',
      body: ListView(padding: const EdgeInsets.all(16), children: [
        Text('Tutoriales con Boxy', style: theme.textTheme.headlineSmall),
        const Text('Elige un módulo para repasar su recorrido.'),
        const SizedBox(height: 12),
        for (final tutorial in tutorials)
          Builder(builder: (context) {
            final enabled = user?.enabledModules.contains(tutorial.id) ?? false;
            return Card(
              margin: const EdgeInsets.only(bottom: 12),
              child: ExpansionTile(
                shape: const Border(),
                leading: Icon(enabled ? Icons.school_outlined : Icons.lock_outline),
                title: Text(tutorial.title),
                subtitle: Text(enabled ? tutorial.description : 'Este módulo no está activo para tu empresa.'),
                children: [
                  if (enabled)
                    for (final (index, step) in tutorial.steps.indexed)
                      ListTile(
                        leading: CircleAvatar(radius: 14, child: Text('${index + 1}', style: const TextStyle(fontSize: 12))),
                        title: Text(step.title),
                        subtitle: Text(step.text),
                        trailing: step.path == null ? null : const Icon(Icons.chevron_right),
                        onTap: step.path == null ? null : () => context.push(step.path!),
                      ),
                ],
              ),
            );
          }),
      ]),
    );
  }
}
