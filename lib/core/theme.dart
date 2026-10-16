import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Color principal por defecto de la web (themePalette.ts → DEFAULT_PRIMARY).
const brandColor = Color(0xFF4F46E5);

/// Mismas paletas que el personalizador de apariencia de la web.
const accentPalettes = <(String, Color)>[
  ('Índigo', Color(0xFF4F46E5)),
  ('Océano', Color(0xFF0077CC)),
  ('Bosque', Color(0xFF059669)),
  ('Atardecer', Color(0xFFEA580C)),
  ('Rosa', Color(0xFFDB2777)),
  ('Grafito', Color(0xFF64748B)),
];

Color _mix(Color color, Color target, double amount) => Color.lerp(color, target, amount)!;

/// Tokens del tema de la web (createTheme en themePalette.ts y Navigation.css).
@immutable
class MiColors extends ThemeExtension<MiColors> {
  const MiColors({
    required this.primary,
    required this.background,
    required this.surface,
    required this.text,
    required this.muted,
    required this.border,
    required this.input,
    required this.accent,
    required this.navDark,
    required this.navDarkEnd,
    required this.navHighlight,
    required this.navSelected,
    required this.primarySoft,
    required this.danger,
    required this.success,
    required this.warning,
  });

  final Color primary, background, surface, text, muted, border, input, accent;

  /// Menú lateral: degradado oscuro teñido del color principal.
  final Color navDark, navDarkEnd, navHighlight, navSelected;
  final Color primarySoft, danger, success, warning;

  factory MiColors.of(Color primary, Brightness brightness) {
    final dark = brightness == Brightness.dark;
    const night = Color(0xFF0B1020);
    return MiColors(
      primary: primary,
      background: _mix(dark ? const Color(0xFF0C1018) : const Color(0xFFF3F5FA), primary, dark ? .06 : .025),
      surface: _mix(dark ? const Color(0xFF161B25) : Colors.white, primary, dark ? .07 : .015),
      text: dark ? const Color(0xFFE9EDF5) : const Color(0xFF182238),
      muted: dark ? const Color(0xFF9AA5B8) : const Color(0xFF6B778C),
      border: _mix(dark ? const Color(0xFF303847) : const Color(0xFFDCE1EA), primary, .07),
      input: _mix(dark ? const Color(0xFF101620) : Colors.white, primary, .025),
      accent: dark ? _mix(primary, Colors.white, .4) : _mix(primary, Colors.black, .15),
      navDark: _mix(night, primary, .2),
      navDarkEnd: _mix(night, primary, .1),
      navHighlight: _mix(Colors.white, primary, .35),
      navSelected: _mix(const Color(0x10FFFFFF), primary, .28),
      primarySoft: primary.withValues(alpha: dark ? .2 : .1),
      danger: const Color(0xFFD14343),
      success: const Color(0xFF0A8A4A),
      warning: const Color(0xFFD97706),
    );
  }

  @override
  MiColors copyWith() => this;

  @override
  MiColors lerp(ThemeExtension<MiColors>? other, double t) => other is MiColors && t > .5 ? other : this;
}

extension MiTheme on BuildContext {
  MiColors get mi => Theme.of(this).extension<MiColors>()!;
}

/// "Eyebrow" de la web: mayúsculas pequeñas con espaciado.
TextStyle eyebrow(BuildContext context, {Color? color}) => TextStyle(
      fontSize: 11,
      fontWeight: FontWeight.w700,
      letterSpacing: 1.4,
      color: color ?? context.mi.muted,
    );

ThemeData buildTheme(Brightness brightness, [Color primary = brandColor]) {
  final mi = MiColors.of(primary, brightness);
  final scheme = ColorScheme.fromSeed(seedColor: primary, brightness: brightness).copyWith(
    primary: primary,
    onPrimary: Colors.white,
    surface: mi.surface,
    onSurface: mi.text,
    onSurfaceVariant: mi.muted,
    outline: mi.muted,
    outlineVariant: mi.border,
    error: mi.danger,
  );
  final base = ThemeData(colorScheme: scheme, useMaterial3: true, brightness: brightness);
  final text = base.textTheme;
  TextStyle? w(TextStyle? style, FontWeight weight) => style?.copyWith(fontWeight: weight, color: mi.text);
  final radius = BorderRadius.circular(10);
  OutlineInputBorder border(Color color, [double width = 1]) =>
      OutlineInputBorder(borderRadius: radius, borderSide: BorderSide(color: color, width: width));

  return base.copyWith(
    scaffoldBackgroundColor: mi.background,
    extensions: [mi],
    textTheme: text.copyWith(
      headlineMedium: w(text.headlineMedium, FontWeight.w700),
      headlineSmall: w(text.headlineSmall, FontWeight.w700),
      titleLarge: w(text.titleLarge, FontWeight.w700),
      titleMedium: w(text.titleMedium, FontWeight.w600),
      titleSmall: w(text.titleSmall, FontWeight.w600),
      bodyLarge: w(text.bodyLarge, FontWeight.w400),
      bodyMedium: w(text.bodyMedium, FontWeight.w400),
      bodySmall: text.bodySmall?.copyWith(color: mi.muted),
      labelLarge: w(text.labelLarge, FontWeight.w600),
      labelSmall: text.labelSmall?.copyWith(color: mi.muted),
    ),
    // Barra superior de la web: superficie con borde inferior.
    appBarTheme: AppBarTheme(
      centerTitle: false,
      backgroundColor: mi.surface,
      foregroundColor: mi.text,
      surfaceTintColor: Colors.transparent,
      elevation: 0,
      scrolledUnderElevation: 0,
      shape: Border(bottom: BorderSide(color: mi.border)),
      titleTextStyle: TextStyle(fontSize: 19, fontWeight: FontWeight.w600, color: mi.text, letterSpacing: -.3),
    ),
    cardTheme: CardThemeData(
      color: mi.surface,
      elevation: 0,
      margin: EdgeInsets.zero,
      surfaceTintColor: Colors.transparent,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14), side: BorderSide(color: mi.border)),
    ),
    dividerTheme: DividerThemeData(color: mi.border, space: 1),
    listTileTheme: ListTileThemeData(iconColor: mi.muted),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: mi.input,
      contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
      border: border(mi.border),
      enabledBorder: border(mi.border),
      focusedBorder: border(primary, 1.6),
      labelStyle: TextStyle(color: mi.muted),
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        backgroundColor: primary,
        foregroundColor: Colors.white,
        minimumSize: const Size(48, 46),
        shape: RoundedRectangleBorder(borderRadius: radius),
        textStyle: const TextStyle(fontWeight: FontWeight.w600),
      ),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        foregroundColor: mi.text,
        minimumSize: const Size(48, 46),
        side: BorderSide(color: mi.border),
        shape: RoundedRectangleBorder(borderRadius: radius),
      ),
    ),
    floatingActionButtonTheme: FloatingActionButtonThemeData(
      backgroundColor: primary,
      foregroundColor: Colors.white,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
    ),
    chipTheme: base.chipTheme.copyWith(side: BorderSide(color: mi.border)),
    drawerTheme: DrawerThemeData(backgroundColor: mi.navDark, width: 300),
    snackBarTheme: const SnackBarThemeData(behavior: SnackBarBehavior.floating),
  );
}

/// Tema claro/oscuro/sistema y color de acento, guardados en el dispositivo.
class ThemeController extends ChangeNotifier {
  ThemeMode mode = ThemeMode.system;
  Color primary = brandColor;

  Future<void> load() async {
    final prefs = await SharedPreferences.getInstance();
    mode = ThemeMode.values.asNameMap()[prefs.getString('theme_mode')] ?? ThemeMode.system;
    final saved = prefs.getInt('theme_primary');
    if (saved != null) primary = Color(saved);
    notifyListeners();
  }

  Future<void> setMode(ThemeMode value) async {
    mode = value;
    notifyListeners();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('theme_mode', value.name);
  }

  Future<void> setPrimary(Color value) async {
    primary = value;
    notifyListeners();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt('theme_primary', value.toARGB32());
  }
}
