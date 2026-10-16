import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../core/boxy_guide.dart';
import '../core/modules.dart';
import '../core/session.dart';
import '../core/theme.dart';
import '../core/user_profile.dart';
import 'boxy_face.dart';
import 'boxy_overlay.dart';

/// Envuelve las pantallas con sesión: muestra a Boxy encima y, con biometría
/// activa, bloquea la app si estuvo más de [lockAfter] en segundo plano.
class AppShell extends StatefulWidget {
  const AppShell({super.key, required this.location, required this.child});
  final Uri location;
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
    WidgetsBinding.instance.addPostFrameCallback((_) => context.read<BoxyGuide>().onLocation(widget.location));
  }

  @override
  void didUpdateWidget(AppShell old) {
    super.didUpdateWidget(old);
    if (old.location != widget.location) {
      final location = widget.location;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) context.read<BoxyGuide>().onLocation(location);
      });
    }
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
  Widget build(BuildContext context) => Stack(children: [
        Positioned.fill(child: widget.child),
        const Positioned(left: 0, right: 0, bottom: 0, child: BoxyOverlay()),
      ]);
}

bool _matches(String location, String path) {
  final target = path.split('?').first;
  return target == '/' ? location == '/' : location == target || location.startsWith('$target/');
}

/// Ruta del menú que corresponde a la pantalla: la coincidencia más larga, para
/// que /suppliers/orders/5 marque "Órdenes de compra" y no también "Proveedores".
String? activeMenuPath(String location, UserProfile? user) {
  String? best;
  for (final entry in visibleModules(user)) {
    for (final path in [if (entry.path != null && !entry.locked) entry.path!, for (final item in entry.items ?? const <MenuItem>[]) item.path]) {
      if (_matches(location, path) && (best == null || path.length > best.length)) best = path;
    }
  }
  if (best == null && _matches(location, '/settings')) best = '/settings';
  return best;
}

/// Grupo del menú al que pertenece la pantalla (el "eyebrow" de la barra superior).
String? menuGroupOf(String location, UserProfile? user) {
  final active = activeMenuPath(location, user);
  for (final entry in visibleModules(user)) {
    if (entry.items?.any((item) => item.path == active) ?? false) return entry.title;
  }
  return null;
}

/// Menú lateral oscuro como el sidebar de la web: un grupo abierto a la vez.
class AppDrawer extends StatefulWidget {
  const AppDrawer({super.key});

  @override
  State<AppDrawer> createState() => _AppDrawerState();
}

class _AppDrawerState extends State<AppDrawer> {
  String? _open;
  bool _initialized = false;

  @override
  Widget build(BuildContext context) {
    final user = context.watch<SessionController>().profile;
    final location = GoRouterState.of(context).uri.path;
    final mi = context.mi;
    final modules = visibleModules(user);
    final activePath = activeMenuPath(location, user);
    bool isActive(String path) => path == activePath;
    if (!_initialized) {
      _initialized = true;
      _open = menuGroupOf(location, user);
    }

    void go(String path) {
      Navigator.of(context).pop();
      context.go(path);
    }

    void locked(MenuEntry entry) {
      Navigator.of(context).pop();
      final messenger = ScaffoldMessenger.of(context);
      messenger.showSnackBar(SnackBar(
        content: Text('${entry.title} no está activo. Actívalo en Integraciones dentro de Administración.'),
        action: (user?.isAdmin ?? false) ? SnackBarAction(label: 'Ver', onPressed: () => context.go(integrationsPath)) : null,
      ));
    }

    return Drawer(
      child: DecoratedBox(
        decoration: BoxDecoration(
          gradient: LinearGradient(begin: Alignment.topCenter, end: Alignment.bottomCenter, colors: [mi.navDark, mi.navDarkEnd]),
        ),
        child: SafeArea(
          child: ListView(padding: const EdgeInsets.fromLTRB(12, 8, 12, 16), children: [
            Container(
              height: 96,
              margin: const EdgeInsets.only(bottom: 16),
              decoration: const BoxDecoration(border: Border(bottom: BorderSide(color: Color(0x12FFFFFF)))),
              child: Image.asset('assets/images/mi-inventario.logo.png', fit: BoxFit.contain, cacheHeight: 288),
            ),
            const Padding(
              padding: EdgeInsets.fromLTRB(12, 0, 12, 12),
              child: Text('ESPACIO DE TRABAJO',
                  style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600, letterSpacing: 1.8, color: Color(0xFFAAB3CC))),
            ),
            for (final entry in modules)
              if (entry.divider)
                Container(
                  margin: const EdgeInsets.fromLTRB(8, 12, 8, 6),
                  padding: const EdgeInsets.only(top: 10),
                  decoration: const BoxDecoration(border: Border(top: BorderSide(color: Color(0x14FFFFFF)))),
                  child: entry.title == null
                      ? null
                      : Padding(
                          padding: const EdgeInsets.only(left: 4),
                          child: Text(entry.title!.toUpperCase(),
                              style: const TextStyle(fontSize: 10.5, fontWeight: FontWeight.w700, letterSpacing: 1.6, color: Color(0xFFAAB3CC))),
                        ),
                )
              else if (entry.locked)
                _NavItem(icon: entry.icon!, label: entry.title!, trailing: Icons.lock_outline, onTap: () => locked(entry))
              else if (entry.items == null)
                _NavItem(icon: entry.icon!, label: entry.title!, active: isActive(entry.path!), onTap: () => go(entry.path!))
              else ...[
                _NavItem(
                  icon: entry.icon!,
                  label: entry.title!,
                  open: _open == entry.title,
                  current: entry.items!.any((item) => isActive(item.path)),
                  trailing: Icons.expand_more,
                  onTap: () => setState(() => _open = _open == entry.title ? null : entry.title),
                ),
                AnimatedSize(
                  duration: const Duration(milliseconds: 260),
                  curve: Curves.easeOut,
                  child: _open == entry.title
                      ? Container(
                          margin: const EdgeInsets.fromLTRB(13, 4, 0, 8),
                          padding: const EdgeInsets.fromLTRB(10, 4, 4, 4),
                          decoration: BoxDecoration(
                            color: const Color(0x20000000),
                            borderRadius: BorderRadius.circular(10),
                            border: const Border(left: BorderSide(color: Color(0x18FFFFFF))),
                          ),
                          child: Column(children: [
                            for (final item in entry.items!)
                              _NavItem(icon: item.icon, label: item.label, nested: true, active: isActive(item.path), onTap: () => go(item.path)),
                          ]),
                        )
                      : const SizedBox(width: double.infinity),
                ),
              ],
            Container(
              margin: const EdgeInsets.fromLTRB(8, 12, 8, 6),
              decoration: const BoxDecoration(border: Border(top: BorderSide(color: Color(0x14FFFFFF)))),
            ),
            _NavItem(icon: Icons.manage_accounts_outlined, label: 'Mi perfil y ajustes', active: isActive('/settings'), onTap: () => go('/settings')),
          ]),
        ),
      ),
    );
  }
}

class _NavItem extends StatelessWidget {
  const _NavItem({
    required this.icon,
    required this.label,
    required this.onTap,
    this.active = false,
    this.current = false,
    this.open = false,
    this.nested = false,
    this.trailing,
  });
  final IconData icon;
  final String label;
  final VoidCallback onTap;
  final bool active, current, open, nested;
  final IconData? trailing;

  @override
  Widget build(BuildContext context) {
    final mi = context.mi;
    final bright = active || open || current;
    // Submódulo abierto: fondo de selección y barra. Módulo que lo contiene:
    // fondo teñido más suave y la misma barra, aunque esté plegado.
    final background = active
        ? mi.navSelected
        : current
            ? mi.navHighlight.withValues(alpha: .1)
            : (open ? const Color(0x07FFFFFF) : Colors.transparent);
    final marked = active || current;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Material(
        color: background,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(10),
          side: BorderSide(color: marked ? const Color(0x18FFFFFF) : Colors.transparent),
        ),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onTap,
          child: Container(
            constraints: BoxConstraints(minHeight: nested ? 44 : 48),
            decoration: BoxDecoration(border: Border(left: BorderSide(color: marked ? mi.navHighlight : Colors.transparent, width: 3))),
            padding: const EdgeInsets.fromLTRB(9, 0, 12, 0),
            child: Row(children: [
              Icon(icon, size: nested ? 20 : 21, color: active || current ? mi.navHighlight : (bright ? Colors.white : const Color(0xFFC6CDE0))),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: bright ? Colors.white : const Color(0xFFC6CDE0),
                    fontSize: nested ? 14.5 : 15.5,
                    fontWeight: active || current ? FontWeight.w700 : (nested ? FontWeight.w400 : FontWeight.w600),
                  ),
                ),
              ),
              if (trailing != null)
                AnimatedRotation(
                  turns: trailing == Icons.expand_more && open ? .5 : 0,
                  duration: const Duration(milliseconds: 200),
                  child: Icon(trailing, size: 18, color: const Color(0xFFAAB3CC)),
                ),
            ]),
          ),
        ),
      ),
    );
  }
}

const _roleLabels = {
  'admin': 'Administrador',
  'manager': 'Gerente',
  'operator': 'Operador',
  'auditor': 'Auditor',
  'warehouse': 'Almacén',
  'maintance': 'Mantenimiento',
  'user': 'Usuario',
};

String roleLabel(String role) => _roleLabels[role] ?? role;

/// Botón de Boxy de la barra superior: abre su ayuda.
class BoxyButton extends StatelessWidget {
  const BoxyButton({super.key});

  @override
  Widget build(BuildContext context) => IconButton(
        tooltip: 'Ayuda de Boxy',
        onPressed: () => context.read<BoxyGuide>().openHelp(),
        icon: const BoxyFace(size: 30, animate: false),
      );
}

/// Avatar con el menú de perfil (como el de la barra superior de la web).
class ProfileMenu extends StatelessWidget {
  const ProfileMenu({super.key});

  @override
  Widget build(BuildContext context) {
    final session = context.watch<SessionController>();
    final user = session.profile;
    final mi = context.mi;
    final picture = user?.profilePictureUrl;
    final initials = (user?.displayName ?? '')
        .split(' ')
        .where((part) => part.isNotEmpty)
        .take(2)
        .map((part) => part[0].toUpperCase())
        .join();
    return PopupMenuButton<String>(
      tooltip: 'Perfil',
      offset: const Offset(0, 48),
      onSelected: (value) {
        if (value == 'logout') {
          session.logout();
        } else if (value == 'boxy') {
          context.read<BoxyGuide>().openHelp();
        } else {
          context.go(value);
        }
      },
      itemBuilder: (context) => [
        PopupMenuItem(
          enabled: false,
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(user?.displayName ?? '', style: Theme.of(context).textTheme.titleSmall),
            Text('${roleLabel(user?.role ?? '')} · ${user?.accountName ?? ''}', style: Theme.of(context).textTheme.bodySmall),
          ]),
        ),
        const PopupMenuDivider(),
        const PopupMenuItem(value: '/settings', child: ListTile(dense: true, leading: Icon(Icons.manage_accounts_outlined), title: Text('Mi perfil y ajustes'))),
        if (user?.isAdmin ?? false)
          const PopupMenuItem(value: '/account-settings', child: ListTile(dense: true, leading: Icon(Icons.settings_outlined), title: Text('Ajustes de cuenta'))),
        const PopupMenuItem(value: 'boxy', child: ListTile(dense: true, leading: Icon(Icons.support_agent), title: Text('Ayuda de Boxy'))),
        PopupMenuItem(
          value: 'logout',
          child: ListTile(dense: true, leading: Icon(Icons.logout, color: mi.danger), title: Text('Cerrar sesión', style: TextStyle(color: mi.danger))),
        ),
      ],
      child: Padding(
        padding: const EdgeInsets.fromLTRB(4, 6, 10, 6),
        child: Container(
          width: 36,
          height: 36,
          decoration: BoxDecoration(
            color: mi.navDark,
            borderRadius: BorderRadius.circular(11),
            border: Border.all(color: mi.border),
            image: (picture?.isNotEmpty ?? false) ? DecorationImage(image: NetworkImage(picture!), fit: BoxFit.cover) : null,
          ),
          alignment: Alignment.center,
          child: (picture?.isNotEmpty ?? false)
              ? null
              : Text(initials.isEmpty ? '?' : initials, style: TextStyle(color: mi.navHighlight, fontWeight: FontWeight.w700, fontSize: 13)),
        ),
      ),
    );
  }
}

/// Scaffold estándar de una pantalla del menú: arriba el módulo y la pantalla
/// (Inventario › Productos), Boxy y el perfil, igual que la barra de la web.
class ModuleScaffold extends StatelessWidget {
  const ModuleScaffold({super.key, required this.title, required this.body, this.actions, this.floatingActionButton, this.bottom});
  final String title;
  final Widget body;
  final List<Widget>? actions;
  final Widget? floatingActionButton;
  final PreferredSizeWidget? bottom;

  @override
  Widget build(BuildContext context) {
    final user = context.watch<SessionController>().profile;
    final group = menuGroupOf(GoRouterState.of(context).uri.path, user);
    return Scaffold(
      appBar: AppBar(
        titleSpacing: 0,
        title: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
          if (group != null) Text(group.toUpperCase(), style: eyebrow(context, color: context.mi.primary)),
          Text(title, maxLines: 1, overflow: TextOverflow.ellipsis),
        ]),
        actions: [...?actions, const BoxyButton(), const ProfileMenu()],
        bottom: bottom,
      ),
      drawer: const AppDrawer(),
      body: SafeArea(top: false, child: body),
      floatingActionButton: floatingActionButton,
    );
  }
}
