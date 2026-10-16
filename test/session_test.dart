import 'dart:convert';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:mi_inventario_mobile/core/api_client.dart';
import 'package:mi_inventario_mobile/core/session.dart';
import 'package:shared_preferences/shared_preferences.dart';

Map<String, dynamic> sessionJson(String refresh, {String access = 'access-1'}) => {
      'access_token': access,
      'expires_in': 900,
      'refresh_token': refresh,
      'user': {'id': 1, 'email': 'ana@example.com', 'first_name': 'Ana', 'role': 'admin'},
      'account': {'id': 3, 'name': 'Empresa', 'status': 'trial'},
    };

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    FlutterSecureStorage.setMockInitialValues({});
  });

  test('login stores the refresh token and API calls send the Bearer token', () async {
    final seen = <String, String?>{};
    final api = ApiClient(client: MockClient((request) async {
      if (request.url.path == '/api/mobile/v1/session') {
        return http.Response(jsonEncode(sessionJson('refresh-1')), 200);
      }
      seen[request.url.path] = request.headers['Authorization'];
      return http.Response('{"ok":true}', 200);
    }));
    final session = SessionController(api);
    await session.start();
    expect(session.status, SessionStatus.signedOut);

    await session.login(' Ana@Example.com ', 'secreta');
    expect(session.status, SessionStatus.signedIn);
    expect(session.profile!.firstName, 'Ana');
    expect(await const FlutterSecureStorage().read(key: 'refresh_token'), 'refresh-1');

    await api.get('/products');
    expect(seen['/products'], 'Bearer access-1');
  });

  test('a stored session is resumed by rotating the refresh token', () async {
    FlutterSecureStorage.setMockInitialValues({'refresh_token': 'old'});
    String? sent;
    final api = ApiClient(client: MockClient((request) async {
      sent = jsonDecode(request.body)['refresh_token'];
      return http.Response(jsonEncode(sessionJson('new')), 200);
    }));
    final session = SessionController(api);
    await session.start();
    expect(sent, 'old');
    expect(session.status, SessionStatus.signedIn);
    expect(await const FlutterSecureStorage().read(key: 'refresh_token'), 'new');
  });

  test('with biometrics enabled the app starts locked without calling the API', () async {
    FlutterSecureStorage.setMockInitialValues({'refresh_token': 'old'});
    SharedPreferences.setMockInitialValues({'biometric_enabled': true});
    var calls = 0;
    final session = SessionController(ApiClient(client: MockClient((_) async {
      calls++;
      return http.Response('{}', 200);
    })));
    await session.start();
    expect(session.status, SessionStatus.locked);
    expect(calls, 0);
  });

  test('a rejected refresh token signs the user out with a notice', () async {
    FlutterSecureStorage.setMockInitialValues({'refresh_token': 'old'});
    final session = SessionController(ApiClient(client: MockClient((_) async {
      return http.Response(jsonEncode({'error': 'Tu sesión expiró. Inicia sesión de nuevo.'}), 401);
    })));
    await session.start();
    expect(session.status, SessionStatus.signedOut);
    expect(session.notice, contains('expiró'));
    expect(await const FlutterSecureStorage().read(key: 'refresh_token'), isNull);
  });

  test('a 401 from the API refreshes once and retries the request', () async {
    var productCalls = 0;
    var refreshes = 0;
    final api = ApiClient(client: MockClient((request) async {
      switch (request.url.path) {
        case '/api/mobile/v1/session':
          return http.Response(jsonEncode(sessionJson('r1')), 200);
        case '/api/mobile/v1/session/refresh':
          refreshes++;
          return http.Response(jsonEncode(sessionJson('r2', access: 'access-2')), 200);
        default:
          productCalls++;
          return request.headers['Authorization'] == 'Bearer access-2'
              ? http.Response('{"data":[],"meta":{"total":0,"total_pages":0}}', 200)
              : http.Response('{}', 401);
      }
    }));
    final session = SessionController(api);
    await session.start();
    await session.login('ana@example.com', 'x');
    final page = PageResult.fromJson(await api.get('/products'));
    expect(page.items, isEmpty);
    expect(productCalls, 2);
    expect(refreshes, 1);
  });

  test('API errors carry the server message and subscription state', () async {
    final api = ApiClient(client: MockClient((_) async => http.Response(
        jsonEncode({'error': 'subscription_inactive', 'message': 'Tu cuenta aún no tiene un plan.'}), 402,
        headers: {'content-type': 'application/json; charset=utf-8'})));
    try {
      await api.send('GET', '/products', auth: false);
      fail('should throw');
    } on ApiException catch (error) {
      expect(error.subscriptionInactive, isTrue);
      expect(error.message, 'Tu cuenta aún no tiene un plan.');
    }
  });
}
