import 'dart:math' as math;

import 'package:flutter/material.dart';

/// Mismas expresiones que el modelo 3D de la web (sin enojo: no regaña).
enum BoxyExpression { feliz, neutro, duda, sorprendido, tristeza }

/// Boxy, la caja de cartón del logo, dibujada en 2D: flota, parpadea y mueve
/// la boca mientras [speaking] es verdadero.
class BoxyFace extends StatefulWidget {
  const BoxyFace({super.key, this.size = 96, this.expression = BoxyExpression.feliz, this.speaking = false, this.animate = true});
  final double size;
  final BoxyExpression expression;
  final bool speaking;

  /// Sin animación (íconos pequeños o movimiento reducido): pose fija.
  final bool animate;

  @override
  State<BoxyFace> createState() => _BoxyFaceState();
}

class _BoxyFaceState extends State<BoxyFace> with SingleTickerProviderStateMixin {
  late final AnimationController _clock = AnimationController(vsync: this, duration: const Duration(seconds: 60));
  final _random = math.Random();
  double _nextBlink = 2.5;
  double _blinkUntil = 0;

  @override
  void initState() {
    super.initState();
    if (widget.animate) _clock.repeat();
  }

  @override
  void didUpdateWidget(BoxyFace old) {
    super.didUpdateWidget(old);
    if (widget.animate && !_clock.isAnimating) _clock.repeat();
    if (!widget.animate && _clock.isAnimating) _clock.stop();
  }

  @override
  void dispose() {
    _clock.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final still = !widget.animate || MediaQuery.of(context).disableAnimations;
    return RepaintBoundary(
      child: AnimatedBuilder(
        animation: _clock,
        builder: (context, _) {
          final t = _clock.value * 60;
          if (!still && t > _nextBlink) {
            _blinkUntil = t + .14;
            _nextBlink = t + 2.5 + _random.nextDouble() * 3;
          }
          // Al reiniciar el reloj (cada minuto) se reprograma el parpadeo.
          if (_nextBlink - t > 10) _nextBlink = t + 1;
          final blinking = !still && t < _blinkUntil;
          final mouth = widget.speaking && !still ? (math.sin(t * 17) * .5 + .5) * (.55 + .45 * math.sin(t * 5.3).abs()) : 0.0;
          final float = still ? 0.0 : math.sin(t * 1.6) * widget.size * .025;
          return Transform.translate(
            offset: Offset(0, float),
            child: CustomPaint(
              size: Size.square(widget.size),
              painter: _BoxyPainter(expression: widget.expression, blink: blinking, mouth: mouth),
            ),
          );
        },
      ),
    );
  }
}

class _BoxyPainter extends CustomPainter {
  _BoxyPainter({required this.expression, required this.blink, required this.mouth});
  final BoxyExpression expression;
  final bool blink;
  final double mouth;

  static const _outline = Color(0xFF1B1F2A);
  static const _front = Color(0xFFE3A35E);
  static const _side = Color(0xFFC9813F);
  static const _top = Color(0xFFF0BD7E);
  static const _tape = Color(0xFFF7D9A8);
  static const _blush = Color(0xFFF28C93);

  @override
  void paint(Canvas canvas, Size size) {
    final s = size.width;
    final stroke = Paint()
      ..color = _outline
      ..style = PaintingStyle.stroke
      ..strokeWidth = s * .035
      ..strokeJoin = StrokeJoin.round
      ..strokeCap = StrokeCap.round;
    Paint fill(Color c) => Paint()..color = c;

    // Caja en perspectiva: frente, lado derecho y tapa.
    final front = RRect.fromLTRBR(s * .1, s * .3, s * .74, s * .92, Radius.circular(s * .05));
    final side = Path()
      ..moveTo(s * .74, s * .32)
      ..lineTo(s * .9, s * .2)
      ..lineTo(s * .9, s * .8)
      ..lineTo(s * .74, s * .92)
      ..close();
    final top = Path()
      ..moveTo(s * .12, s * .3)
      ..lineTo(s * .28, s * .17)
      ..lineTo(s * .9, s * .2)
      ..lineTo(s * .74, s * .31)
      ..close();
    canvas.drawPath(side, fill(_side));
    canvas.drawPath(side, stroke);
    canvas.drawPath(top, fill(_top));
    canvas.drawPath(top, stroke);
    canvas.drawRRect(front, fill(_front));
    canvas.drawRRect(front, stroke);

    // Cinta de la tapa.
    final tape = Path()
      ..moveTo(s * .44, s * .18)
      ..lineTo(s * .56, s * .185)
      ..lineTo(s * .48, s * .31)
      ..lineTo(s * .36, s * .31)
      ..close();
    canvas.drawPath(tape, fill(_tape));

    // Etiqueta con código de barras.
    final label = RRect.fromLTRBR(s * .17, s * .74, s * .33, s * .86, Radius.circular(s * .015));
    canvas.drawRRect(label, fill(Colors.white));
    canvas.drawRRect(label, stroke..strokeWidth = s * .018);
    final bars = Paint()
      ..color = _outline
      ..strokeWidth = s * .014;
    for (var i = 0; i < 5; i++) {
      final x = s * (.2 + i * .026);
      canvas.drawLine(Offset(x, s * .765), Offset(x, s * .835), bars);
    }
    stroke.strokeWidth = s * .035;

    // Cachetes.
    canvas.drawOval(Rect.fromCenter(center: Offset(s * .22, s * .6), width: s * .1, height: s * .06), fill(_blush.withValues(alpha: .8)));
    canvas.drawOval(Rect.fromCenter(center: Offset(s * .63, s * .6), width: s * .1, height: s * .06), fill(_blush.withValues(alpha: .8)));

    _eyes(canvas, s);
    _brows(canvas, s, stroke);
    _mouth(canvas, s, stroke);
  }

  void _eyes(Canvas canvas, double s) {
    final left = Offset(s * .3, s * .5);
    final right = Offset(s * .55, s * .5);
    final dark = Paint()..color = _outline;
    final big = expression == BoxyExpression.sorprendido ? 1.2 : 1.0;
    for (final center in [left, right]) {
      if (blink) {
        canvas.drawLine(center - Offset(s * .04, 0), center + Offset(s * .04, 0), Paint()
          ..color = _outline
          ..strokeWidth = s * .03
          ..strokeCap = StrokeCap.round);
        continue;
      }
      canvas.drawOval(Rect.fromCenter(center: center, width: s * .09 * big, height: s * .11 * big), dark);
      canvas.drawCircle(center + Offset(s * .015, -s * .022), s * .018 * big, Paint()..color = Colors.white);
    }
  }

  void _brows(Canvas canvas, double s, Paint stroke) {
    final brow = Paint()
      ..color = _outline
      ..strokeWidth = s * .022
      ..strokeCap = StrokeCap.round;
    switch (expression) {
      case BoxyExpression.duda:
        canvas.drawLine(Offset(s * .25, s * .4), Offset(s * .34, s * .38), brow);
        canvas.drawLine(Offset(s * .51, s * .36), Offset(s * .6, s * .4), brow);
      case BoxyExpression.tristeza:
        canvas.drawLine(Offset(s * .25, s * .41), Offset(s * .34, s * .38), brow);
        canvas.drawLine(Offset(s * .51, s * .38), Offset(s * .6, s * .41), brow);
      case BoxyExpression.sorprendido:
        canvas.drawArc(Rect.fromCenter(center: Offset(s * .3, s * .38), width: s * .1, height: s * .05), math.pi, math.pi, false, brow);
        canvas.drawArc(Rect.fromCenter(center: Offset(s * .55, s * .38), width: s * .1, height: s * .05), math.pi, math.pi, false, brow);
      case BoxyExpression.feliz:
      case BoxyExpression.neutro:
        break;
    }
  }

  void _mouth(Canvas canvas, double s, Paint stroke) {
    final center = Offset(s * .425, s * .64);
    final line = Paint()
      ..color = _outline
      ..style = PaintingStyle.stroke
      ..strokeWidth = s * .026
      ..strokeCap = StrokeCap.round;
    final talking = mouth > .05;
    if (talking || expression == BoxyExpression.feliz || expression == BoxyExpression.sorprendido) {
      // Boca abierta: sonrisa con lengua; al hablar se abre y cierra.
      final surprised = expression == BoxyExpression.sorprendido && !talking;
      // Sonrisa en "D": borde superior recto y fondo curvo; al hablar baja la mandíbula.
      final open = surprised ? .1 : (talking ? .035 + mouth * .07 : .07);
      final width = surprised ? .08 : .16;
      final rect = Rect.fromLTWH(center.dx - s * width / 2, center.dy - s * .02, s * width, s * open);
      final path = surprised
          ? (Path()..addOval(rect))
          : (Path()
            ..moveTo(rect.left, rect.top)
            ..lineTo(rect.right, rect.top)
            ..cubicTo(rect.right, rect.bottom + rect.height * .35, rect.left, rect.bottom + rect.height * .35, rect.left, rect.top)
            ..close());
      canvas.drawPath(path, Paint()..color = const Color(0xFF5B1A24));
      canvas.save();
      canvas.clipPath(path);
      canvas.drawOval(Rect.fromCenter(center: Offset(center.dx, rect.bottom), width: rect.width * .6, height: rect.height * .7), Paint()..color = const Color(0xFFF07A8A));
      canvas.restore();
      canvas.drawPath(path, line..strokeWidth = s * .02);
      return;
    }
    switch (expression) {
      case BoxyExpression.tristeza:
        canvas.drawArc(Rect.fromCenter(center: center + Offset(0, s * .03), width: s * .12, height: s * .06), math.pi * 1.1, math.pi * .8, false, line);
      case BoxyExpression.duda:
        canvas.drawLine(center - Offset(s * .05, 0), center + Offset(s * .05, -s * .015), line);
      default:
        canvas.drawArc(Rect.fromCenter(center: center - Offset(0, s * .02), width: s * .12, height: s * .06), math.pi * .15, math.pi * .7, false, line);
    }
  }

  @override
  bool shouldRepaint(_BoxyPainter old) => old.expression != expression || old.blink != blink || old.mouth != mouth;
}
