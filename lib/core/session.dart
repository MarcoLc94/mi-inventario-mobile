import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:local_auth/local_auth.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'api_client.dart';
import 'user_profile.dart';

enum SessionStatus { starting, signedOut, locked, signedIn }

/// Sesión de la app: access token corto en memoria y refresh token rotatorio
/// en el almacenamiento cifrado de Android (MobileSessionsController en el
/// backend). Con biometría activa, la app arranca bloqueada y solo renueva el
/// token después de verificar la huella o el rostro.
class SessionController extends ChangeNotifier implements TokenProvider {
  SessionController(this.api) {
    api.tokens = this;
  }

  final ApiClient api;
  static const _storage = FlutterSecureStorage();
  static const _refreshKey = 'refresh_token';
  static const _profileKey = 'profile';
  static const _biometricKey = 'biometric_enabled';
  final _localAuth = LocalAuthentication();

  SessionStatus status = SessionStatus.starting;
  UserProfile? profile;
  bool biometricEnabled = false;
  String? notice;

  String? _accessToken;
  DateTime? _accessExpiresAt;
  String? _refreshToken;
  Future<void>? _refreshing;

  bool get signedIn => status == SessionStatus.signedIn;

  Future<void> start() async {
    final prefs = await SharedPreferences.getInstance();
    biometricEnabled = prefs.getBool(_biometricKey) ?? false;
    try {
      _refreshToken = await _storage.read(key: _refreshKey);
      final saved = await _storage.read(key: _profileKey);
      if (saved != null) profile = UserProfile.fromSession(asMap(jsonDecode(saved)));
    } catch (_) {
      // Almacenamiento ilegible (p. ej. tras restaurar un respaldo): se pide login.
      _refreshToken = null;
    }

    if (_refreshToken == null) {
      _setStatus(SessionStatus.signedOut);
    } else if (biometricEnabled) {
      _setStatus(SessionStatus.locked);
    } else {
      await _resume();
    }
  }

  Future<void> _resume() async {
    try {
      await _refresh();
      _setStatus(SessionStatus.signedIn);
    } on ApiException catch (error) {
      if (error.status == 401) {
        await _clear(notice: error.message);
      } else if (profile != null) {
        // Sin conexión: se entra con los datos guardados y se reintenta al pedir datos.
        _setStatus(SessionStatus.signedIn);
      } else {
        notice = error.message;
        _setStatus(SessionStatus.signedOut);
      }
    }
  }

  Future<void> login(String email, String password) async {
    final data = await api.send('POST', '/api/mobile/v1/session', auth: false, body: {
      'email': email.trim().toLowerCase(),
      'password': password,
      'device_name': 'Android',
    });
    await _saveSession(asMap(data));
    notice = null;
    _setStatus(SessionStatus.signedIn);
  }

  /// Desbloqueo con huella/rostro. Devuelve false si el usuario lo cancela.
  Future<bool> unlock() async {
    final ok = await _authenticate('Desbloquea Mi Inventario');
    if (!ok) return false;
    await _resume();
    return status == SessionStatus.signedIn;
  }

  /// Bloquea la app (al volver de segundo plano con biometría activa).
  void lock() {
    if (status == SessionStatus.signedIn && biometricEnabled && _refreshToken != null) {
      _accessToken = null;
      _setStatus(SessionStatus.locked);
    }
  }

  Future<bool> biometricsAvailable() async {
    try {
      return await _localAuth.isDeviceSupported() && await _localAuth.canCheckBiometrics;
    } catch (_) {
      return false;
    }
  }

  Future<void> setBiometrics(bool enabled) async {
    if (enabled) {
      if (!await biometricsAvailable()) {
        throw ApiException(0, 'Configura una huella o rostro en los ajustes de Android para activarlo.');
      }
      if (!await _authenticate('Confirma para activar el acceso con huella')) return;
    }
    biometricEnabled = enabled;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_biometricKey, enabled);
    notifyListeners();
  }

  Future<bool> _authenticate(String reason) async {
    try {
      return await _localAuth.authenticate(localizedReason: reason, biometricOnly: true, persistAcrossBackgrounding: true);
    } catch (_) {
      return false;
    }
  }

  /// Vuelve a pedir /me para actualizar permisos y módulos (p. ej. tras pagar).
  Future<void> reloadProfile() async {
    final data = asMap(await api.get('/me'));
    final current = profile;
    profile = UserProfile(asMap(data['user']),
        account: asMap(data['account']), permissions: current?.permissions ?? const {});
    await _storage.write(key: _profileKey, value: jsonEncode(profile!.toJson()));
    notifyListeners();
  }

  Future<void> logout() async {
    try {
      if (_accessToken != null) await api.delete('/api/mobile/v1/session');
    } catch (_) {
      // El cierre local siempre gana, también sin conexión.
    }
    await _clear();
  }

  /// Cierra la sesión local mostrando un aviso en el login (p. ej. tras eliminar la cuenta).
  Future<void> endSession({String? notice}) => _clear(notice: notice);

  @override
  Future<String?> accessToken({bool forceRefresh = false}) async {
    final expires = _accessExpiresAt;
    final fresh = _accessToken != null &&
        expires != null &&
        expires.isAfter(DateTime.now().add(const Duration(seconds: 60)));
    if (fresh && !forceRefresh) return _accessToken;
    if (_refreshToken == null || status == SessionStatus.locked) return null;
    try {
      await _refresh();
    } on ApiException catch (error) {
      if (error.status == 401) await _clear(notice: error.message);
      return null;
    }
    return _accessToken;
  }

  @override
  Future<void> onUnauthorized() => _clear(notice: 'Tu sesión expiró. Inicia sesión de nuevo.');

  Future<void> _refresh() {
    // Una sola renovación a la vez: el refresh token rota y no se puede reutilizar.
    return _refreshing ??= _doRefresh().whenComplete(() => _refreshing = null);
  }

  Future<void> _doRefresh() async {
    final token = _refreshToken;
    if (token == null) throw ApiException(401, 'Inicia sesión de nuevo.');
    final data = await api.send('POST', '/api/mobile/v1/session/refresh', auth: false, body: {'refresh_token': token});
    await _saveSession(asMap(data));
  }

  Future<void> _saveSession(Map<String, dynamic> data) async {
    final refresh = data['refresh_token']?.toString();
    if (refresh == null || refresh.isEmpty) throw ApiException(0, 'La respuesta de sesión está incompleta.');
    // Guardar el token rotado antes que nada: el anterior ya no sirve.
    await _storage.write(key: _refreshKey, value: refresh);
    _refreshToken = refresh;
    _accessToken = data['access_token']?.toString();
    _accessExpiresAt = DateTime.now().add(Duration(seconds: (data['expires_in'] as num?)?.toInt() ?? 900));
    profile = UserProfile.fromSession(data);
    await _storage.write(key: _profileKey, value: jsonEncode(profile!.toJson()));
  }

  Future<void> _clear({String? notice}) async {
    if (status == SessionStatus.signedOut && _refreshToken == null) return;
    _accessToken = null;
    _accessExpiresAt = null;
    _refreshToken = null;
    profile = null;
    this.notice = notice;
    try {
      await _storage.delete(key: _refreshKey);
      await _storage.delete(key: _profileKey);
    } catch (_) {}
    _setStatus(SessionStatus.signedOut);
  }

  void _setStatus(SessionStatus value) {
    status = value;
    notifyListeners();
  }
}
