import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:provider/provider.dart';

import 'core/api_client.dart';
import 'core/boxy_guide.dart';
import 'core/catalogs.dart';
import 'core/push.dart';
import 'core/session.dart';
import 'core/theme.dart';
import 'router.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await initializeDateFormatting('es_MX');
  final api = ApiClient();
  final session = SessionController(api);
  final catalogs = Catalogs(api);
  session.addListener(() {
    if (!session.signedIn && session.status != SessionStatus.locked) catalogs.clear();
  });
  final themeController = ThemeController();
  await themeController.load();
  final push = PushService(api, session);
  runApp(MiInventarioApp(api: api, session: session, catalogs: catalogs, themeController: themeController, push: push));
  await push.initialize();
  session.start();
}

class MiInventarioApp extends StatefulWidget {
  const MiInventarioApp({super.key, required this.api, required this.session, required this.catalogs, required this.themeController, required this.push});
  final ApiClient api;
  final SessionController session;
  final Catalogs catalogs;
  final ThemeController themeController;
  final PushService push;

  @override
  State<MiInventarioApp> createState() => _MiInventarioAppState();
}

class _MiInventarioAppState extends State<MiInventarioApp> {
  late final GoRouter _router = buildRouter(widget.session);
  late final BoxyGuide _boxy = BoxyGuide(widget.api, widget.session);

  @override
  void initState() {
    super.initState();
    widget.push.pendingPath.addListener(_openPushPath);
    // Si la app se abrió desde una notificación, espera a que haya sesión.
    widget.session.addListener(_openPushPath);
  }

  /// Al tocar una notificación: abre su pantalla cuando ya hay sesión.
  void _openPushPath() {
    final path = widget.push.pendingPath.value;
    if (path == null || path.isEmpty || !widget.session.signedIn) return;
    widget.push.pendingPath.value = null;
    _router.push(path);
  }

  @override
  void dispose() {
    widget.push.pendingPath.removeListener(_openPushPath);
    widget.session.removeListener(_openPushPath);
    _boxy.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => MultiProvider(
        providers: [
          Provider.value(value: widget.api),
          Provider.value(value: widget.catalogs),
          ChangeNotifierProvider.value(value: widget.session),
          ChangeNotifierProvider.value(value: widget.themeController),
          ChangeNotifierProvider.value(value: _boxy),
          ChangeNotifierProvider.value(value: widget.push),
        ],
        child: Consumer<ThemeController>(
          builder: (context, theme, _) => MaterialApp.router(
            title: 'Mi Inventario',
            debugShowCheckedModeBanner: false,
            theme: buildTheme(Brightness.light, theme.primary),
            darkTheme: buildTheme(Brightness.dark, theme.primary),
            themeMode: theme.mode,
            locale: const Locale('es', 'MX'),
            supportedLocales: const [Locale('es', 'MX'), Locale('es')],
            localizationsDelegates: GlobalMaterialLocalizations.delegates,
            routerConfig: _router,
          ),
        ),
      );
}
