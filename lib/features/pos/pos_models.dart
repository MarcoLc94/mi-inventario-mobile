import '../../core/formatters.dart';
import '../../core/user_profile.dart';

const posMethods = {'cash': 'Efectivo', 'card': 'Tarjeta', 'transfer': 'Transferencia'};

/// Partida del carrito. La cantidad va en la presentación elegida; el
/// servidor calcula precios e IVA con POST /pos/quote.
class CartLine {
  CartLine({required this.product, required this.presentation, this.quantity = 1});
  final Map<String, dynamic> product;
  String presentation;
  num quantity;

  int get productId => (product['id'] as num).toInt();
  String get name => product['name']?.toString() ?? '';
  List<Map<String, dynamic>> get presentations => asMapList(product['presentations']).where((p) => p['ref'] != 'base').toList();
  num get factor => toNum(presentations.where((p) => p['ref'] == presentation).firstOrNull?['factor']) ?? 1;
  num get baseQuantity => quantity * factor;
  String get key => '$productId|$presentation';

  Map<String, dynamic> toJson() => {'product_id': productId, 'quantity': quantity, 'presentation': presentation};
}

/// Cantidad del producto ya en el carrito, en unidad base (todas sus presentaciones).
num baseInCart(List<CartLine> cart, int productId) =>
    cart.where((l) => l.productId == productId).fold<num>(0, (sum, l) => sum + l.baseQuantity);

String money(dynamic value) => formatMoney(toNum(value) ?? 0);
