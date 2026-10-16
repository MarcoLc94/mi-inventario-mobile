import 'dart:convert';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:mi_inventario_mobile/core/api_client.dart';
import 'package:mi_inventario_mobile/core/push.dart';
import 'package:mi_inventario_mobile/core/session.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    FlutterSecureStorage.setMockInitialValues({});
  });

  test('loads the notices, counts unread and marks them as read', () async {
    final reads = <Object?>[];
    final api = ApiClient(client: MockClient((request) async {
      switch (request.url.path) {
        case '/api/mobile/v1/session':
          return http.Response(
              jsonEncode({
                'access_token': 'a',
                'expires_in': 900,
                'refresh_token': 'r',
                'user': {'id': 1, 'email': 'ana@example.com', 'first_name': 'Ana', 'role': 'admin'},
                'account': {'id': 3, 'name': 'Empresa', 'status': 'active'},
              }),
              200);
        case '/app_notifications':
          return http.Response(
              jsonEncode({
                'unread': 2,
                'notifications': [
                  {'id': 2, 'kind': 'lots', 'title': 'Lotes por caducar', 'body': '1 lote', 'path': '/inventory/lots', 'read': false, 'created_at': '2026-10-16T14:00:00Z'},
                  {'id': 1, 'kind': 'stock', 'title': 'Stock bajo: Arroz', 'body': 'Quedan 2', 'path': '/products/9', 'read': false, 'created_at': '2026-10-16T13:00:00Z'},
                ],
              }),
              200);
        case '/app_notifications/read':
          reads.add(jsonDecode(request.body));
          return http.Response(jsonEncode({'unread': reads.length == 1 ? 1 : 0}), 200);
      }
      return http.Response('{}', 404);
    }));
    final session = SessionController(api);
    await session.start();
    final push = PushService(api, session);
    await session.login('ana@example.com', 'x');
    await Future<void>.delayed(const Duration(milliseconds: 50));

    expect(push.unread, 2);
    expect(push.notices.map((n) => n.title), ['Lotes por caducar', 'Stock bajo: Arroz']);

    await push.markRead(push.notices.last);
    expect(push.unread, 1);
    expect(push.notices.last.read, isTrue);
    expect(reads.single, {'ids': [1]});

    await push.markRead();
    expect(push.unread, 0);
    expect(push.notices.every((n) => n.read), isTrue);
  });
}
