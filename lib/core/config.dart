/// URLs del backend y de la web. Se pueden cambiar al compilar:
/// `flutter run --dart-define=API_BASE_URL=https://api.mi-inventario.space`.
class AppConfig {
  static const apiBaseUrl = String.fromEnvironment(
    'API_BASE_URL',
    defaultValue: 'https://api.mi-inventario.space',
  );

  /// Web de Mi Inventario: se abre para lo que todavía no existe en la app
  /// (por ejemplo, elegir plan o pagar con Stripe).
  static const webBaseUrl = String.fromEnvironment(
    'WEB_BASE_URL',
    defaultValue: 'https://app.mi-inventario.space',
  );
}
