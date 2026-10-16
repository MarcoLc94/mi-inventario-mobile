import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:provider/provider.dart';

import 'core/api_client.dart';
import 'core/catalogs.dart';
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
  runApp(MiInventarioApp(api: api, session: session, catalogs: catalogs, themeController: themeController));
  session.start();
}

class MiInventarioApp extends StatefulWidget {
  const MiInventarioApp({super.key, required this.api, required this.session, required this.catalogs, required this.themeController});
  final ApiClient api;
  final SessionController session;
  final Catalogs catalogs;
  final ThemeController themeController;

  @override
  State<MiInventarioApp> createState() => _MiInventarioAppState();
}

class _MiInventarioAppState extends State<MiInventarioApp> {
  late final GoRouter _router = buildRouter(widget.session);

  @override
  Widget build(BuildContext context) => MultiProvider(
        providers: [
          Provider.value(value: widget.api),
          Provider.value(value: widget.catalogs),
          ChangeNotifierProvider.value(value: widget.session),
          ChangeNotifierProvider.value(value: widget.themeController),
        ],
        child: Consumer<ThemeController>(
          builder: (context, theme, _) => MaterialApp.router(
            title: 'Mi Inventario',
            debugShowCheckedModeBanner: false,
            theme: buildTheme(Brightness.light),
            darkTheme: buildTheme(Brightness.dark),
            themeMode: theme.mode,
            locale: const Locale('es', 'MX'),
            supportedLocales: const [Locale('es', 'MX'), Locale('es')],
            localizationsDelegates: GlobalMaterialLocalizations.delegates,
            routerConfig: _router,
          ),
        ),
      );
}
