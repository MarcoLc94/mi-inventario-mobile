import 'dart:async';

import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'api_client.dart';
import 'session.dart';
import 'user_profile.dart';

const _channel = AndroidNotificationChannel(
  'alerts',
  'Avisos de Mi Inventario',
  description: 'Stock bajo, órdenes por vencer, lotes por caducar, caja y plan',
  importance: Importance.high,
);

/// Un aviso de la pantalla Avisos (GET /app_notifications).
class AppNotice {
  AppNotice(Map<String, dynamic> json)
      : id = (json['id'] as num).toInt(),
        kind = json['kind']?.toString() ?? '',
        title = json['title']?.toString() ?? '',
        body = json['body']?.toString() ?? '',
        path = json['path']?.toString(),
        read = json['read'] == true,
        createdAt = DateTime.tryParse(json['created_at']?.toString() ?? '')?.toLocal();
  final int id;
  final String kind, title, body;
  final String? path;
  bool read;
  final DateTime? createdAt;
}

/// Avisos de la app: notificaciones push (Firebase) y la lista de Avisos.
/// Sin android/app/google-services.json no hay push, pero la lista funciona.
class PushService extends ChangeNotifier {
  PushService(this.api, this.session) {
    session.addListener(_sessionChanged);
    session.beforeLogout.add(_unregister);
  }

  final ApiClient api;
  final SessionController session;
  final _local = FlutterLocalNotificationsPlugin();

  /// Ruta a abrir al tocar una notificación.
  final pendingPath = ValueNotifier<String?>(null);

  bool pushAvailable = false;
  List<AppNotice> notices = const [];
  int unread = 0;
  bool loading = false;
  String? _token;
  int? _userId;
  StreamSubscription<String>? _refresh;
  var _nextId = 0;

  Future<void> initialize() async {
    try {
      await _local.initialize(
        settings: const InitializationSettings(android: AndroidInitializationSettings('@mipmap/ic_launcher')),
        onDidReceiveNotificationResponse: (response) => pendingPath.value = response.payload,
      );
      await _local.resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>()?.createNotificationChannel(_channel);
      final launch = await _local.getNotificationAppLaunchDetails();
      if (launch?.didNotificationLaunchApp ?? false) pendingPath.value = launch!.notificationResponse?.payload;
    } catch (error) {
      debugPrint('Notificaciones locales no disponibles: $error');
    }
    try {
      await Firebase.initializeApp();
      pushAvailable = true;
      FirebaseMessaging.onMessage.listen((message) {
        // Con la app abierta Android no muestra el push: lo mostramos nosotros.
        unawaited(_show(message.notification?.title ?? 'Mi Inventario', message.notification?.body ?? '', message.data['path']?.toString()));
        unawaited(refresh());
      });
      FirebaseMessaging.onMessageOpenedApp.listen((message) => pendingPath.value = message.data['path']?.toString());
      final initial = await FirebaseMessaging.instance.getInitialMessage();
      if (initial != null) pendingPath.value = initial.data['path']?.toString();
    } catch (error) {
      debugPrint('Push desactivado (falta configurar Firebase): $error');
    }
    _sessionChanged();
  }

  Future<void> _show(String title, String body, String? path) async {
    try {
      await _local.show(
        id: _nextId++ % 1000,
        title: title,
        body: body,
        payload: path,
        notificationDetails: NotificationDetails(
          android: AndroidNotificationDetails(_channel.id, _channel.name,
              channelDescription: _channel.description, importance: Importance.high, priority: Priority.high),
        ),
      );
    } catch (_) {}
  }

  void _sessionChanged() {
    final id = session.signedIn ? session.profile?.id : null;
    if (id == _userId) return;
    _userId = id;
    if (id == null) {
      notices = const [];
      unread = 0;
      notifyListeners();
      return;
    }
    unawaited(_register());
    unawaited(refresh());
  }

  /// Pide permiso (Android 13+) la primera vez y registra el token del teléfono.
  Future<void> _register() async {
    if (!pushAvailable) return;
    try {
      final prefs = await SharedPreferences.getInstance();
      if (!(prefs.getBool('push-permission-asked') ?? false)) {
        await prefs.setBool('push-permission-asked', true);
        await FirebaseMessaging.instance.requestPermission();
      }
      // getToken/onTokenRefresh dan el token de registro que espera el campo
      // `token` de FCM v1 en el backend (register() entrega otro identificador).
      // ignore: deprecated_member_use
      _token = await FirebaseMessaging.instance.getToken();
      if (_token != null) await api.post('/api/mobile/v1/devices', {'token': _token, 'platform': 'android'});
      await _refresh?.cancel();
      // ignore: deprecated_member_use
      _refresh = FirebaseMessaging.instance.onTokenRefresh.listen((token) {
        _token = token;
        unawaited(api.post('/api/mobile/v1/devices', {'token': token, 'platform': 'android'}).catchError((_) {}));
      });
    } catch (error) {
      debugPrint('No se registró el teléfono para push: $error');
    }
  }

  Future<void> _unregister() async {
    await _refresh?.cancel();
    _refresh = null;
    final token = _token;
    if (token == null) return;
    await api.delete('/api/mobile/v1/devices', {'token': token});
    _token = null;
  }

  Future<void> refresh() async {
    if (!session.signedIn) return;
    loading = true;
    notifyListeners();
    try {
      final data = asMap(await api.get('/app_notifications'));
      notices = asMapList(data['notifications']).map(AppNotice.new).toList();
      unread = (data['unread'] as num?)?.toInt() ?? 0;
    } catch (_) {
      // Sin conexión: se conserva la lista anterior.
    } finally {
      loading = false;
      notifyListeners();
    }
  }

  Future<void> markRead([AppNotice? notice]) async {
    if (notice != null && notice.read) return;
    for (final item in notices) {
      if (notice == null || item.id == notice.id) item.read = true;
    }
    unread = notice == null ? 0 : (unread - 1).clamp(0, 1 << 30);
    notifyListeners();
    try {
      final data = asMap(await api.post('/app_notifications/read', notice == null ? {} : {'ids': [notice.id]}));
      unread = (data['unread'] as num?)?.toInt() ?? unread;
      notifyListeners();
    } catch (_) {}
  }

  @override
  void dispose() {
    session.removeListener(_sessionChanged);
    session.beforeLogout.remove(_unregister);
    _refresh?.cancel();
    super.dispose();
  }
}
