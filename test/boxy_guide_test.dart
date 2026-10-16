import 'dart:convert';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:mi_inventario_mobile/core/api_client.dart';
import 'package:mi_inventario_mobile/core/boxy_guide.dart';
import 'package:mi_inventario_mobile/core/session.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  var progress = <String, bool>{};

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    FlutterSecureStorage.setMockInitialValues({});
    progress = {'warehouse': true, 'product': false};
  });

  Future<BoxyGuide> signedIn() async {
    final api = ApiClient(client: MockClient((request) async {
      if (request.url.path == '/api/mobile/v1/session') {
        return http.Response(
            jsonEncode({
              'access_token': 'a',
              'expires_in': 900,
              'refresh_token': 'r',
              'user': {'id': 7, 'email': 'ana@example.com', 'first_name': 'Ana', 'role': 'admin', 'account_enabled_modules': ['inventory']},
              'account': {'id': 3, 'name': 'Empresa', 'status': 'active'},
            }),
            200);
      }
      if (request.url.path == '/inventory_tutorial') return http.Response(jsonEncode(progress), 200);
      return http.Response('{"error":"sin voz"}', 503);
    }));
    final session = SessionController(api);
    await session.start();
    await session.login('ana@example.com', 'x');
    final guide = BoxyGuide(api, session);
    await Future<void>.delayed(const Duration(milliseconds: 50));
    return guide;
  }

  test('greets once per user and opens the module tutorial on its screen', () async {
    final guide = await signedIn();
    expect(guide.helpOpen, isTrue);
    expect(guide.welcome, isTrue);
    expect(guide.dialogue, boxyWelcome);

    guide.close();
    guide.onLocation(Uri.parse('/products'));
    expect(guide.tutorial?.id, 'inventory');
    expect(guide.guiding, isTrue);
    expect(guide.step, 0);

    final second = await signedIn();
    expect(second.welcome, isFalse, reason: 'la bienvenida es solo la primera vez');
  });

  test('Continuar checks the step requirement before advancing', () async {
    final guide = await signedIn();
    guide.close();
    guide.start('inventory');
    guide.onLocation(Uri.parse('/products'));

    expect(await guide.advance(), '/warehouses', reason: 'el paso 1 se hace en Almacenes');
    expect(guide.step, 1);

    guide.onLocation(Uri.parse('/warehouses'));
    expect(await guide.advance(), '/products');
    expect(guide.step, 2);

    guide.onLocation(Uri.parse('/products'));
    expect(await guide.advance(), isNull);
    expect(guide.notice, boxyPending, reason: 'todavía no hay producto');
    expect(guide.step, 2);

    progress['product'] = true;
    expect(await guide.advance(), '/inventory/manual?type=IN');
    expect(guide.step, 3);
  });
}
