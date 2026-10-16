import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  // El login, el splash y la pantalla de bloqueo usan el logo; sin declararlo
  // en pubspec.yaml la app muestra "asset not found".
  test('el logo está empaquetado como asset', () async {
    final data = await rootBundle.load('assets/images/mi-inventario.logo.png');
    expect(data.lengthInBytes, greaterThan(0));
  });
}
