import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../core/modules.dart';
import '../core/session.dart';

/// Envuelve las pantallas con sesión: con biometría activa, bloquea la app si
/// estuvo más de [lockAfter] en segundo plano.
class AppShell extends StatefulWidget {
  const AppShell({super.key, required this.child});
  final Widget child;
  static const lockAfter = Duration(minutes: 3);

  @override
  State<AppShell> createState() => _AppShellState();
}

class _AppShellState extends State<AppShell> with WidgetsBindingObserver {
  DateTime? _pausedAt;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.paused) _pausedAt = DateTime.now();
    if (state == AppLifecycleState.resumed) {
      final paused = _pausedAt;
      _pausedAt = null;
      if (paused != null && DateTime.now().difference(paused) > AppShell.lockAfter) {
        context.read<SessionController>().lock();
      }
    }
  }

  @override
  Widget build(BuildContext context) => widget.child;
}

class AppDrawer extends StatelessWidget {
  const AppDrawer({super.key});

  @override
  Widget build(BuildContext context) {
    final session = context.watch<SessionController>();
    final user = session.profile;
    final location = GoRouterState.of(context).uri.path;
    final theme = Theme.of(context);
    final modules = visibleModules(user);

    void go(String path) {
      Navigator.of(context).pop();
      context.go(path);
    }

    return NavigationDrawer(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(24, 20, 16, 12),
          child: Row(children: [
            CircleAvatar(
              radius: 22,
              backgroundImage: (user?.profilePictureUrl?.isNotEmpty ?? false) ? NetworkImage(user!.profilePictureUrl!) : null,
              child: (user?.profilePictureUrl?.isNotEmpty ?? false)
                  ? null
                  : Text((user?.displayName.isNotEmpty ?? false) ? user!.displayName[0].toUpperCase() : '?'),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(user?.displayName ?? '', style: theme.textTheme.titleSmall, overflow: TextOverflow.ellipsis),
                Text(user?.accountName ?? '', style: theme.textTheme.bodySmall, overflow: TextOverflow.ellipsis),
              ]),
            ),
          ]),
        ),
        const Divider(indent: 16, endIndent: 16),
        for (final entry in modules)
          if (entry.divider)
            Padding(
              padding: const EdgeInsets.fromLTRB(28, 12, 16, 4),
              child: entry.title == null
                  ? const Divider()
                  : Text(entry.title!.toUpperCase(),
                      style: theme.textTheme.labelSmall?.copyWith(color: theme.colorScheme.outline, letterSpacing: 1.1)),
            )
          else if (entry.items == null)
            _tile(context, entry.icon, entry.title!, entry.path!, location, go, locked: entry.locked)
          else
            ExpansionTile(
              leading: Icon(entry.icon),
              title: Text(entry.title!),
              shape: const Border(),
              initiallyExpanded: entry.items!.any((item) => _active(location, item.path)),
              childrenPadding: const EdgeInsets.only(left: 12),
              children: [for (final item in entry.items!) _tile(context, item.icon, item.label, item.path, location, go)],
            ),
        const Divider(indent: 16, endIndent: 16),
        _tile(context, Icons.manage_accounts_outlined, 'Mi perfil y ajustes', '/settings', location, go),
        const SizedBox(height: 16),
      ],
    );
  }

  static bool _active(String location, String path) =>
      path == '/' ? location == '/' : location == path || location.startsWith('$path/');

  Widget _tile(BuildContext context, IconData? icon, String label, String path, String location,
      void Function(String) go,
      {bool locked = false}) {
    final selected = !locked && _active(location, path.split('?').first);
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12),
      child: ListTile(
        leading: Icon(icon),
        title: Text(label),
        trailing: locked ? const Icon(Icons.lock_outline, size: 18) : null,
        selected: selected,
        selectedTileColor: Theme.of(context).colorScheme.secondaryContainer,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(28)),
        onTap: () => go(path),
      ),
    );
  }
}

/// Scaffold estándar de una pantalla del menú.
class ModuleScaffold extends StatelessWidget {
  const ModuleScaffold({super.key, required this.title, required this.body, this.actions, this.floatingActionButton, this.bottom});
  final String title;
  final Widget body;
  final List<Widget>? actions;
  final Widget? floatingActionButton;
  final PreferredSizeWidget? bottom;

  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(title: Text(title), actions: actions, bottom: bottom),
        drawer: const AppDrawer(),
        body: SafeArea(top: false, child: body),
        floatingActionButton: floatingActionButton,
      );
}
