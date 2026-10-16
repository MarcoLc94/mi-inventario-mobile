// Genera assets/images/app_icon.png (1024x1024) recortando la mascota del logo.
// Uso: dart run tool/make_icon.dart
import 'dart:io';

import 'package:image/image.dart' as img;

void main() {
  final logo = img.decodePng(File('assets/images/mi-inventario.logo.png').readAsBytesSync())!;
  // La caja (sin el texto de la derecha) ocupa aprox. x 20–588, y 205–773 del logo de 1536x1024.
  final crop = img.copyCrop(logo, x: 20, y: 205, width: 568, height: 568);
  // Quita el brillo blanco de la letra "i" que asoma a la derecha: en esa
  // esquina, los pixeles grises o blancos (no la mano) pasan a fondo oscuro.
  // Además, el fondo gris muy oscuro se vuelve uniforme para que no se note el corte.
  for (final pixel in crop) {
    final r = pixel.r.toInt(), g = pixel.g.toInt(), b = pixel.b.toInt();
    final gray = (r - g).abs() < 28 && (g - b).abs() < 28;
    final corner = pixel.x >= 470 && pixel.y >= 300;
    if (gray && ((corner && r > 40) || r < 60)) {
      pixel
        ..r = 12
        ..g = 12
        ..b = 14;
    }
  }
  final icon = img.copyResize(crop, width: 1024, height: 1024, interpolation: img.Interpolation.cubic);
  File('assets/images/app_icon.png').writeAsBytesSync(img.encodePng(icon));
  // Primer plano del ícono adaptable: mismo dibujo con margen (zona segura del 66 %).
  final canvas = img.Image(width: 1024, height: 1024, numChannels: 4);
  img.fill(canvas, color: img.ColorRgba8(0, 0, 0, 0));
  img.compositeImage(canvas, img.copyResize(crop, width: 700, height: 700, interpolation: img.Interpolation.cubic), dstX: 162, dstY: 162);
  File('assets/images/app_icon_foreground.png').writeAsBytesSync(img.encodePng(canvas));
  stdout.writeln('ok');
}
