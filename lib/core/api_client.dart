import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;

import 'config.dart';
import 'user_profile.dart';

class ApiException implements Exception {
  ApiException(this.status, this.message, [this.body]);

  final int status;
  final String message;
  final Map<String, dynamic>? body;

  /// 402: la cuenta no tiene plan o se venció la prueba (EnforcesSubscription).
  bool get subscriptionInactive => status == 402;

  /// 403 con module_disabled: el módulo no está activo para la empresa.
  bool get moduleDisabled => body?['error'] == 'module_disabled';

  @override
  String toString() => message;
}

/// Proveedor del access token: lo implementa SessionController, que lo
/// renueva con el refresh token cuando está por vencer.
abstract class TokenProvider {
  Future<String?> accessToken({bool forceRefresh = false});
  Future<void> onUnauthorized();
}

/// Cliente HTTP de la API de Mi Inventario. Usa los mismos endpoints que la
/// web, autenticado con `Authorization: Bearer`.
class ApiClient {
  ApiClient({http.Client? client}) : _client = client ?? http.Client();

  final http.Client _client;
  TokenProvider? tokens;

  Uri uri(String path, [Map<String, dynamic>? query]) {
    final base = Uri.parse(AppConfig.apiBaseUrl);
    final params = <String, String>{};
    query?.forEach((key, value) {
      if (value != null && value.toString().isNotEmpty) params[key] = value.toString();
    });
    return base.replace(
      path: '${base.path.replaceAll(RegExp(r'/$'), '')}$path',
      queryParameters: params.isEmpty ? null : params,
    );
  }

  Future<dynamic> get(String path, {Map<String, dynamic>? query}) => send('GET', path, query: query);
  Future<dynamic> post(String path, [Object? body]) => send('POST', path, body: body);
  Future<dynamic> put(String path, [Object? body]) => send('PUT', path, body: body);
  Future<dynamic> patch(String path, [Object? body]) => send('PATCH', path, body: body);
  Future<dynamic> delete(String path, [Object? body]) => send('DELETE', path, body: body);

  /// Envía una petición JSON. Si responde 401 renueva el token una vez y
  /// reintenta; si vuelve a fallar, la sesión se cierra.
  Future<dynamic> send(String method, String path,
      {Map<String, dynamic>? query, Object? body, bool auth = true}) async {
    final response = await _authorized(auth, () {
      final request = http.Request(method, uri(path, query))..headers['Accept'] = 'application/json';
      if (body != null) {
        request.headers['Content-Type'] = 'application/json';
        request.body = jsonEncode(body);
      }
      return request;
    });
    return _decode(response);
  }

  /// Formulario multipart (fotos y documentos). [fields] admite claves
  /// repetidas, como `product[removed_images][]`.
  Future<dynamic> multipart(String method, String path,
      {List<MapEntry<String, String>> fields = const [], List<MapEntry<String, String>> files = const []}) async {
    final response = await _authorized(true, () async {
      final request = http.MultipartRequest(method, uri(path))..headers['Accept'] = 'application/json';
      for (final field in fields) {
        request.fields.containsKey(field.key)
            ? request.files.add(http.MultipartFile.fromString(field.key, field.value))
            : request.fields[field.key] = field.value;
      }
      for (final file in files) {
        request.files.add(await http.MultipartFile.fromPath(file.key, file.value));
      }
      return request;
    });
    return _decode(response);
  }

  /// Descarga un archivo (p. ej. un PDF) y devuelve sus bytes.
  Future<List<int>> download(String path, {Map<String, dynamic>? query}) async {
    final response = await _authorized(true, () => http.Request('GET', uri(path, query)));
    if (response.statusCode >= 200 && response.statusCode < 300) return response.bodyBytes;
    _decode(response);
    throw ApiException(response.statusCode, 'No se pudo descargar el archivo.');
  }

  Future<http.Response> _authorized(bool auth, FutureOr<http.BaseRequest> Function() build) async {
    Future<http.Response> attempt(bool forceRefresh) async {
      final request = await build();
      if (auth) {
        final token = await tokens?.accessToken(forceRefresh: forceRefresh);
        if (token != null) request.headers['Authorization'] = 'Bearer $token';
      }
      final streamed = await _client.send(request).timeout(const Duration(seconds: 60));
      return http.Response.fromStream(streamed);
    }

    var response = await _guard(() => attempt(false));
    if (auth && response.statusCode == 401) {
      response = await _guard(() => attempt(true));
      if (response.statusCode == 401) await tokens?.onUnauthorized();
    }
    return response;
  }

  Future<http.Response> _guard(Future<http.Response> Function() run) async {
    try {
      return await run();
    } on TimeoutException {
      throw ApiException(0, 'El servidor tardó demasiado en responder. Intenta de nuevo.');
    } on http.ClientException {
      throw ApiException(0, 'Sin conexión con el servidor. Revisa tu internet.');
    } on Exception catch (error) {
      if (error is ApiException) rethrow;
      throw ApiException(0, 'Sin conexión con el servidor. Revisa tu internet.');
    }
  }

  dynamic _decode(http.Response response) {
    dynamic data;
    if (response.body.isNotEmpty) {
      try {
        data = jsonDecode(utf8.decode(response.bodyBytes));
      } on FormatException {
        data = null;
      }
    }
    if (response.statusCode >= 200 && response.statusCode < 300) return data;
    final body = asMap(data);
    throw ApiException(response.statusCode, _message(response.statusCode, body), body.isEmpty ? null : body);
  }

  String _message(int status, Map<String, dynamic> body) {
    final errors = body['errors'];
    if (errors is List && errors.isNotEmpty) return errors.join('\n');
    if (errors is Map && errors.isNotEmpty) {
      return errors.entries.map((e) => '${e.key}: ${e.value is List ? (e.value as List).join(', ') : e.value}').join('\n');
    }
    final message = body['message'] ?? (body['error'] is String && body['error'] != 'subscription_inactive' ? body['error'] : null);
    if (message is String && message.isNotEmpty && message != 'module_disabled') return message;
    return switch (status) {
      401 => 'Tu sesión expiró. Inicia sesión de nuevo.',
      402 => 'Tu cuenta no tiene un plan activo.',
      403 => body['error'] == 'module_disabled'
          ? 'Este módulo no está activo para tu empresa.'
          : 'No tienes permiso para realizar esta acción.',
      404 => 'No se encontró el registro.',
      422 => 'Revisa los datos e intenta de nuevo.',
      _ when status >= 500 => 'Ocurrió un error en el servidor. Intenta más tarde.',
      _ => 'No se pudo completar la solicitud.',
    };
  }
}

/// Respuesta paginada estándar de la API: `{ data: [...], meta: { total, total_pages } }`.
class PageResult {
  PageResult(this.items, this.total, this.totalPages);

  factory PageResult.fromJson(dynamic json) {
    final map = asMap(json);
    final meta = asMap(map['meta']);
    return PageResult(
      asMapList(map['data']),
      (meta['total'] as num?)?.toInt() ?? 0,
      (meta['total_pages'] as num?)?.toInt() ?? 1,
    );
  }

  final List<Map<String, dynamic>> items;
  final int total;
  final int totalPages;
}
