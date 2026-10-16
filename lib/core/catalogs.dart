import 'api_client.dart';
import 'formatters.dart';
import 'user_profile.dart';

/// Unidad de medida del catálogo del backend (UnitOfMeasure.as_catalog).
class Unit {
  const Unit({required this.code, required this.name, required this.plural, required this.symbol, required this.decimals});

  factory Unit.fromJson(Map<String, dynamic> json) => Unit(
        code: json['code']?.toString() ?? 'pz',
        name: json['name']?.toString() ?? 'Pieza',
        plural: json['plural']?.toString() ?? 'Piezas',
        symbol: json['symbol']?.toString() ?? 'pz',
        decimals: (json['decimals'] as num?)?.toInt() ?? 0,
      );

  static const piece = Unit(code: 'pz', name: 'Pieza', plural: 'Piezas', symbol: 'pz', decimals: 0);

  final String code;
  final String name;
  final String plural;
  final String symbol;
  final int decimals;

  /// Misma regla que la web: cantidad válida para los decimales de la unidad.
  bool accepts(num value, {bool allowZero = false}) {
    if (value < 0 || (!allowZero && value == 0)) return false;
    final factor = _pow10(decimals);
    return ((value * factor).round() / factor - value).abs() < 1e-9;
  }

  String get precisionMessage =>
      decimals == 0 ? 'Usa cantidades enteras (${plural.toLowerCase()}).' : 'Admite máximo $decimals decimales (${plural.toLowerCase()}).';

  String format(dynamic value) => '${formatNumber(value)} $symbol';

  static num _pow10(int n) => [1, 10, 100, 1000, 10000][n.clamp(0, 4)];
}

/// Catálogos que casi todas las pantallas de inventario necesitan. Se
/// consultan una vez por sesión; [invalidate] los vuelve a pedir.
class Catalogs {
  Catalogs(this.api);
  final ApiClient api;

  Future<List<Unit>>? _units;
  Future<List<Map<String, dynamic>>>? _warehouses;
  Future<List<Map<String, dynamic>>>? _categories;

  Future<List<Unit>> units() => _units ??= api
      .get('/products/units')
      .then((data) => asMapList(asMap(data)['units']).map(Unit.fromJson).toList())
      .catchError((Object error) {
        _units = null;
        throw error;
      });

  Future<Unit> unit(String? code) async {
    final list = await units();
    return list.firstWhere((u) => u.code == (code ?? 'pz'), orElse: () => Unit.piece);
  }

  Future<List<Map<String, dynamic>>> warehouses() => _warehouses ??= api.get('/warehouses').then(asMapList).catchError((Object error) {
        _warehouses = null;
        throw error;
      });

  Future<List<Map<String, dynamic>>> activeWarehouses() async =>
      (await warehouses()).where((w) => w['is_active'] != false).toList();

  Future<List<Map<String, dynamic>>> categories() => _categories ??= api.get('/categories').then(asMapList).catchError((Object error) {
        _categories = null;
        throw error;
      });

  /// Al cerrar sesión: otra cuenta no debe ver los catálogos anteriores.
  void clear() {
    _units = null;
    _warehouses = null;
    _categories = null;
  }

  void invalidate({bool warehouses = false, bool categories = false}) {
    if (warehouses) _warehouses = null;
    if (categories) _categories = null;
  }
}
