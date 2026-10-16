import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/boxy_guide.dart';
import '../../core/theme.dart';
import '../../widgets/app_shell.dart';
import '../../widgets/boxy_face.dart';
import '../../widgets/boxy_overlay.dart';
import 'tutorials_data.dart';

/// Tutoriales: los mismos recorridos de Boxy que en la web. "Empezar" abre la
/// pantalla del primer paso y Boxy acompaña desde ahí.
class TutorialsScreen extends StatelessWidget {
  const TutorialsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final guide = context.watch<BoxyGuide>();
    final theme = Theme.of(context);
    final mi = context.mi;
    return ModuleScaffold(
      title: 'Tutoriales',
      body: ListView(padding: const EdgeInsets.fromLTRB(16, 16, 16, 200), children: [
        Row(children: [
          const BoxyFace(size: 64),
          const SizedBox(width: 12),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text('Aprende con Boxy', style: theme.textTheme.titleLarge),
              Text('Elige un módulo y Boxy te acompaña paso a paso en las pantallas reales.', style: theme.textTheme.bodySmall),
            ]),
          ),
        ]),
        const SizedBox(height: 16),
        for (final tutorial in tutorials)
          Builder(builder: (context) {
            final enabled = guide.allowed(tutorial.id);
            return Card(
              margin: const EdgeInsets.only(bottom: 12),
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                  Row(children: [
                    Container(
                      width: 40,
                      height: 40,
                      decoration: BoxDecoration(color: mi.primarySoft, borderRadius: BorderRadius.circular(10)),
                      child: Icon(enabled ? (tutorial.id == 'pos' ? Icons.point_of_sale_outlined : Icons.inventory_2_outlined) : Icons.lock_outline,
                          color: mi.primary, size: 21),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        Text(tutorial.title, style: theme.textTheme.titleMedium),
                        Text(enabled ? '${tutorial.steps.length} pasos · ${tutorial.description}' : 'Este módulo no está activo para tu empresa.',
                            style: theme.textTheme.bodySmall),
                      ]),
                    ),
                  ]),
                  const SizedBox(height: 12),
                  FilledButton.icon(
                    onPressed: enabled
                        ? () {
                            final path = guide.start(tutorial.id);
                            if (path != null) openBoxyPath(context, path);
                          }
                        : null,
                    icon: const Icon(Icons.play_arrow),
                    label: const Text('Empezar tutorial'),
                  ),
                ]),
              ),
            );
          }),
      ]),
    );
  }
}
