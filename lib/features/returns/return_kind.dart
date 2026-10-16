import '../../core/api_client.dart';
import '../../core/user_profile.dart';

/// Diferencias entre devoluciones a proveedor y de clientes: mismas pantallas,
/// distintos endpoints y nombres de campos en el backend.
class ReturnKind {
  const ReturnKind._({
    required this.title,
    required this.basePath,
    required this.endpoint,
    required this.paramKey,
    required this.partnerLabel,
    required this.documentLabel,
    required this.documentIdKey,
    required this.documentItemsKey,
    required this.itemsAttributesKey,
    required this.itemsKey,
    required this.totalKey,
    required this.pdfPath,
    required this.reasons,
    required this.conditions,
  });

  final String title;
  final String basePath;
  final String endpoint;
  final String paramKey;
  final String partnerLabel;
  final String documentLabel;
  final String documentIdKey;
  final String documentItemsKey;
  final String itemsAttributesKey;
  final String itemsKey;
  final String totalKey;
  final String pdfPath;
  final Map<String, String> reasons;

  /// Condición de cada partida; la primera es la predeterminada.
  final Map<String, String> conditions;

  bool get isSupplier => this == supplier;

  static const supplier = ReturnKind._(
    title: 'Devoluciones a proveedor',
    basePath: '/suppliers/returns',
    endpoint: '/supplier_returns',
    paramKey: 'supplier_return',
    partnerLabel: 'Proveedor',
    documentLabel: 'Compra',
    documentIdKey: 'purchase_order_id',
    documentItemsKey: 'purchase_order_items',
    itemsAttributesKey: 'supplier_return_items_attributes',
    itemsKey: 'supplier_return_items',
    totalKey: 'total_credit',
    pdfPath: 'download_supplier_return',
    reasons: {'defective': 'Defectuoso', 'wrong_item': 'Artículo incorrecto', 'expired': 'Caducado', 'overstock': 'Exceso de inventario', 'other': 'Otro'},
    conditions: {'good': 'Buen estado', 'damaged': 'Dañado', 'defective': 'Defectuoso'},
  );

  static const client = ReturnKind._(
    title: 'Devoluciones de clientes',
    basePath: '/clients/returns',
    endpoint: '/client_returns',
    paramKey: 'client_return',
    partnerLabel: 'Cliente',
    documentLabel: 'Venta',
    documentIdKey: 'sale_order_id',
    documentItemsKey: 'sale_order_items',
    itemsAttributesKey: 'return_items_attributes',
    itemsKey: 'return_items',
    totalKey: 'total_refund',
    pdfPath: 'download_client_return',
    reasons: {'defective': 'Defectuoso', 'wrong_item': 'Artículo incorrecto', 'not_as_described': 'No es lo que se describió', 'changed_mind': 'Cambió de opinión', 'other': 'Otro'},
    conditions: {'new': 'Nuevo / buen estado', 'damaged': 'Dañado', 'defective': 'Defectuoso'},
  );

  Map<String, dynamic> document(Map<String, dynamic> ret) => asMap(ret[isSupplier ? 'purchase_order' : 'sale_order']);

  String partnerName(Map<String, dynamic> ret) =>
      (isSupplier ? asMap(document(ret)['supplier'])['name'] ?? asMap(ret['supplier'])['name'] : asMap(ret['client'])['name'])?.toString() ?? '—';

  Future<List<Map<String, dynamic>>> partners(ApiClient api) async {
    if (isSupplier) return asMapList(await api.get('/suppliers'));
    return PageResult.fromJson(await api.get('/clients', query: {'per_page': 1000, 'sort_by': 'name', 'sort_dir': 'asc'})).items;
  }

  /// Compras del proveedor o ventas del cliente que se pueden devolver.
  Future<List<Map<String, dynamic>>> documents(ApiClient api, int partnerId) async {
    final docs = asMapList(await api.get(isSupplier ? '/suppliers/$partnerId/purchase_orders' : '/clients/$partnerId/sales'));
    final allowed = isSupplier ? const ['received', 'partially_received'] : const ['approved', 'processing', 'shipped', 'completed'];
    return docs.where((d) => allowed.contains(d['status'])).toList();
  }
}
