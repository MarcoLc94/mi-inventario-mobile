import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../core/boxy_guide.dart';
import '../core/modules.dart';
import '../core/session.dart';
import '../core/theme.dart';
import 'boxy_face.dart';

/// Abre la ruta de un paso: las pantallas del menú reemplazan la actual y las
/// demás (p. ej. la entrada manual) se apilan con botón atrás.
void openBoxyPath(BuildContext context, String path) {
  final menu = {
    for (final entry in allModules) ...[if (entry.path != null) entry.path!, for (final item in entry.items ?? const <MenuItem>[]) item.path],
  };
  if (menu.contains(Uri.parse(path).path)) {
    context.go(path);
  } else {
    context.push(path);
  }
}

/// Boxy encima de la app: bienvenida, ayuda y el paso del tutorial en curso.
class BoxyOverlay extends StatelessWidget {
  const BoxyOverlay({super.key});

  @override
  Widget build(BuildContext context) {
    final guide = context.watch<BoxyGuide>();
    // Con el teclado abierto se aparta para no tapar el formulario.
    if (!guide.showing || MediaQuery.viewInsetsOf(context).bottom > 0) return const SizedBox.shrink();
    return SafeArea(
      top: false,
      child: Align(
        alignment: Alignment.bottomCenter,
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 560),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(10, 0, 10, 10),
            child: Material(
              type: MaterialType.transparency,
              child: AnimatedSwitcher(
                duration: const Duration(milliseconds: 220),
                child: guide.minimized ? _Peek(key: const ValueKey('peek'), guide: guide) : _Bubble(key: const ValueKey('bubble'), guide: guide),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Boxy minimizado: un botón para volver a leer la guía.
class _Peek extends StatelessWidget {
  const _Peek({super.key, required this.guide});
  final BoxyGuide guide;

  @override
  Widget build(BuildContext context) => Align(
        alignment: Alignment.bottomRight,
        child: Material(
          color: context.mi.surface,
          elevation: 6,
          shape: StadiumBorder(side: BorderSide(color: context.mi.border)),
          child: InkWell(
            customBorder: const StadiumBorder(),
            onTap: () => guide.setMinimized(false),
            child: Padding(
              padding: const EdgeInsets.fromLTRB(8, 6, 16, 6),
              child: Row(mainAxisSize: MainAxisSize.min, children: [
                const BoxyFace(size: 34, animate: false),
                const SizedBox(width: 8),
                Text(guide.helpOpen ? 'Ayuda' : 'Leer guía', style: const TextStyle(fontWeight: FontWeight.w600)),
              ]),
            ),
          ),
        ),
      );
}

class _Bubble extends StatelessWidget {
  const _Bubble({super.key, required this.guide});
  final BoxyGuide guide;

  BoxyExpression get _expression {
    if (guide.helpOpen) return BoxyExpression.feliz;
    if (guide.notice.isNotEmpty) return guide.checkFailed ? BoxyExpression.tristeza : BoxyExpression.duda;
    if (guide.busy) return BoxyExpression.neutro;
    if (guide.step == 0 || guide.isLast) return BoxyExpression.feliz;
    return guide.tutorial?.id == 'inventory' && guide.step == 4 ? BoxyExpression.sorprendido : BoxyExpression.neutro;
  }

  Future<void> _continue(BuildContext context) async {
    final path = await guide.advance();
    if (path != null && context.mounted) openBoxyPath(context, path);
  }

  void _basicTutorial(BuildContext context) {
    final path = guide.start('inventory');
    if (path != null) {
      openBoxyPath(context, path);
    } else {
      guide.close();
      context.go('/help/tutorials');
    }
  }

  @override
  Widget build(BuildContext context) {
    final mi = context.mi;
    final theme = Theme.of(context);
    final firstName = context.read<SessionController>().profile?.firstName ?? '';
    final help = guide.helpOpen;
    final tutorial = guide.tutorial;
    final title = help
        ? '${guide.welcome ? '¡Bienvenido a Mi Inventario' : '¡Hola de nuevo'}${firstName.isEmpty ? '' : ', $firstName'}!'
        : (guide.step == 0 && firstName.isNotEmpty ? '¡Hola, $firstName!' : guide.current.title);

    return Container(
      decoration: BoxDecoration(
        color: mi.surface,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: mi.border),
        boxShadow: const [BoxShadow(color: Color(0x33000000), blurRadius: 24, offset: Offset(0, 8))],
      ),
      padding: const EdgeInsets.fromLTRB(12, 8, 6, 12),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, mainAxisSize: MainAxisSize.min, children: [
        Row(children: [
          if (!help && tutorial != null) ...[
            Icon(Icons.auto_awesome, size: 14, color: mi.primary),
            const SizedBox(width: 6),
            Text('${tutorial.title.toUpperCase()}  ${guide.step + 1}/${tutorial.steps.length}', style: eyebrow(context, color: mi.primary)),
          ] else
            Text('BOXY', style: eyebrow(context, color: mi.primary)),
          const Spacer(),
          _SmallButton(
            icon: guide.muted ? Icons.volume_off_outlined : Icons.volume_up_outlined,
            tooltip: guide.muted ? 'Activar voz' : 'Silenciar',
            onTap: guide.toggleMuted,
          ),
          _SmallButton(icon: Icons.replay, tooltip: 'Repetir', onTap: guide.busy ? null : guide.replay),
          _SmallButton(icon: Icons.expand_more, tooltip: 'Minimizar', onTap: () => guide.setMinimized(true)),
          _SmallButton(icon: Icons.close, tooltip: 'Cerrar Boxy', onTap: guide.close),
        ]),
        Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Padding(
            padding: const EdgeInsets.only(top: 4, right: 10),
            child: BoxyFace(size: 76, expression: _expression, speaking: guide.speaking),
          ),
          Expanded(
            child: Padding(
              padding: const EdgeInsets.only(right: 6),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(title, style: theme.textTheme.titleMedium),
                const SizedBox(height: 4),
                ConstrainedBox(
                  constraints: const BoxConstraints(maxHeight: 150),
                  child: SingleChildScrollView(
                    child: _Karaoke(
                      text: help || guide.notice.isEmpty ? guide.dialogue : guide.current.text,
                      revealed: help || guide.notice.isEmpty ? guide.revealed : 1 << 20,
                    ),
                  ),
                ),
                if (!help && guide.notice.isNotEmpty) ...[
                  const SizedBox(height: 6),
                  Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(color: mi.warning.withValues(alpha: .12), borderRadius: BorderRadius.circular(8)),
                    child: _Karaoke(text: guide.notice, revealed: guide.revealed),
                  ),
                ],
                if (guide.voice == BoxyVoice.loading)
                  Padding(padding: const EdgeInsets.only(top: 4), child: Text('Preparando voz…', style: theme.textTheme.bodySmall)),
              ]),
            ),
          ),
        ]),
        if (!help && tutorial != null) ...[
          const SizedBox(height: 10),
          Row(children: [
            for (var i = 0; i < tutorial.steps.length; i++)
              Expanded(
                child: Container(
                  height: 4,
                  margin: const EdgeInsets.symmetric(horizontal: 2),
                  decoration: BoxDecoration(color: i <= guide.step ? mi.primary : mi.border, borderRadius: BorderRadius.circular(4)),
                ),
              ),
            const SizedBox(width: 6),
          ]),
        ],
        const SizedBox(height: 10),
        Padding(
          padding: const EdgeInsets.only(right: 6),
          child: Row(children: [
            Expanded(
              child: OutlinedButton(
                onPressed: guide.busy ? null : (help ? () => _basicTutorial(context) : guide.skip),
                style: OutlinedButton.styleFrom(padding: const EdgeInsets.symmetric(horizontal: 10)),
                child: FittedBox(fit: BoxFit.scaleDown, child: Text(help ? 'Ver tutorial básico' : 'Saltar tutorial', maxLines: 1)),
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: FilledButton(
                onPressed: guide.busy
                    ? null
                    : help
                        ? () {
                            guide.close();
                            context.go('/help/boxy');
                          }
                        : () => _continue(context),
                style: FilledButton.styleFrom(padding: const EdgeInsets.symmetric(horizontal: 10)),
                child: FittedBox(
                  fit: BoxFit.scaleDown,
                  child: Row(mainAxisSize: MainAxisSize.min, children: [
                    Text(help ? 'Hablar con Boxy' : (guide.busy ? 'Comprobando…' : (guide.isLast && guide.onStepScreen ? 'Terminar' : 'Continuar')), maxLines: 1),
                    const SizedBox(width: 4),
                    const Icon(Icons.arrow_forward, size: 17),
                  ]),
                ),
              ),
            ),
          ]),
        ),
      ]),
    );
  }
}

class _SmallButton extends StatelessWidget {
  const _SmallButton({required this.icon, required this.tooltip, required this.onTap});
  final IconData icon;
  final String tooltip;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) => IconButton(
        tooltip: tooltip,
        visualDensity: VisualDensity.compact,
        iconSize: 19,
        onPressed: onTap,
        icon: Icon(icon),
      );
}

/// Texto que se va coloreando conforme Boxy lo dice (KaraokeText de la web).
class _Karaoke extends StatelessWidget {
  const _Karaoke({required this.text, required this.revealed});
  final String text;
  final int revealed;

  @override
  Widget build(BuildContext context) {
    final mi = context.mi;
    final count = revealed.clamp(0, text.length);
    final dark = Theme.of(context).brightness == Brightness.dark;
    // Como en la web: lo dicho se ilumina con el color de enlace del tema.
    final lit = dark ? mi.accent : mi.primary;
    final style = Theme.of(context).textTheme.bodyMedium?.copyWith(height: 1.35, fontWeight: FontWeight.w500);
    return Text.rich(TextSpan(style: style, children: [
      TextSpan(text: text.substring(0, count), style: TextStyle(color: lit)),
      TextSpan(text: text.substring(count), style: TextStyle(color: mi.text)),
    ]));
  }
}
