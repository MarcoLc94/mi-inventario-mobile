import 'dart:io';

import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:provider/provider.dart';

import '../../core/api_client.dart';
import '../../core/catalogs.dart';
import '../../core/formatters.dart';
import '../../core/user_profile.dart';
import '../../widgets/async_states.dart';
import '../../widgets/barcode_scanner.dart';
import '../../widgets/form_fields.dart';

/// Alta y edición de productos. Mismos campos y reglas que la web
/// (src/utils/productCreate.ts y la edición en ProductDetail).
class ProductFormScreen extends StatefulWidget {
  const ProductFormScreen({super.key, this.product});

  /// Producto a editar (JSON de GET /products/:id); null para crear.
  final Map<String, dynamic>? product;

  @override
  State<ProductFormScreen> createState() => _ProductFormScreenState();
}

class _ProductFormScreenState extends State<ProductFormScreen> {
  final _form = GlobalKey<FormState>();
  late final Map<String, dynamic>? _edit = widget.product;
  bool get _editing => _edit != null;

  late final _name = TextEditingController(text: _edit?['name']?.toString());
  late final _description = TextEditingController(text: _edit?['description']?.toString());
  final _stock = TextEditingController(text: '0');
  late final _barcode = TextEditingController(text: _edit?['barcode']?.toString());
  late final _saleBarcode = TextEditingController(text: _edit?['sale_barcode']?.toString());
  late final _purchasePrice = TextEditingController(text: _priceText(_edit?['purchase_price']));
  late final _salePrice = TextEditingController(text: _priceText(_edit?['sale_price']));
  late final _satProduct = TextEditingController(text: _edit?['sat_product_code']?.toString() ?? '01010101');
  late final _satUnit = TextEditingController(text: _edit?['sat_unit_code']?.toString() ?? 'H87');
  final _lotNumber = TextEditingController();
  String? _lotExpiration;

  late int? _categoryId = (_edit?['category_id'] as num?)?.toInt();
  int? _warehouseId;
  late int? _supplierId = (_edit?['supplier_id'] as num?)?.toInt();
  late String _baseUnit = _edit?['base_unit']?.toString() ?? 'pz';

  late bool _withBarcodes = _editing;
  late bool _withPrices = _editing;
  late bool _withBilling = _editing;
  bool _withLot = false;

  final _newImages = <XFile>[];
  final _removedImages = <int>{};

  List<Map<String, dynamic>> _categories = [];
  List<Map<String, dynamic>> _warehouses = [];
  List<Map<String, dynamic>> _suppliers = [];
  List<Unit> _units = [];
  bool _loading = true;
  Object? _loadError;
  bool _saving = false;
  String? _error;

  static String _priceText(dynamic value) {
    final n = toNum(value);
    return n == null || n == 0 ? '' : n.toString();
  }

  Unit get _unit => _units.firstWhere((u) => u.code == _baseUnit, orElse: () => Unit.piece);

  @override
  void initState() {
    super.initState();
    _loadCatalogs();
  }

  @override
  void dispose() {
    for (final c in [_name, _description, _stock, _barcode, _saleBarcode, _purchasePrice, _salePrice, _satProduct, _satUnit, _lotNumber]) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _loadCatalogs() async {
    setState(() {
      _loading = true;
      _loadError = null;
    });
    final api = context.read<ApiClient>();
    final catalogs = context.read<Catalogs>();
    try {
      final results = await Future.wait([
        catalogs.categories(),
        catalogs.activeWarehouses(),
        catalogs.units(),
        api.get('/suppliers').then(asMapList).catchError((_) => <Map<String, dynamic>>[]),
        // Crea (si faltan) la categoría y el almacén por defecto, como la web.
        if (!_editing) api.post('/products/defaults', {}).then(asMap),
      ]);
      if (!mounted) return;
      setState(() {
        _categories = results[0] as List<Map<String, dynamic>>;
        _warehouses = results[1] as List<Map<String, dynamic>>;
        _units = results[2] as List<Unit>;
        _suppliers = results[3] as List<Map<String, dynamic>>;
        if (!_editing) {
          final defaults = results[4] as Map<String, dynamic>;
          _categoryId ??= (asMap(defaults['category'])['id'] as num?)?.toInt();
          _warehouseId ??= (asMap(defaults['warehouse'])['id'] as num?)?.toInt() ??
              (_warehouses.length == 1 ? (_warehouses.first['id'] as num).toInt() : null);
          context.read<Catalogs>().invalidate(categories: true, warehouses: true);
        }
      });
    } catch (error) {
      if (mounted) setState(() => _loadError = error);
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _scanInto(TextEditingController controller) async {
    final code = await scanBarcode(context);
    if (code != null) setState(() => controller.text = code);
  }

  Future<void> _addImage(ImageSource source) async {
    final picker = ImagePicker();
    final files = source == ImageSource.camera
        ? [?await picker.pickImage(source: source, imageQuality: 80, maxWidth: 1600)]
        : await picker.pickMultiImage(imageQuality: 80, maxWidth: 1600);
    if (files.isNotEmpty) setState(() => _newImages.addAll(files));
  }

  String? _validate() {
    if (_name.text.trim().isEmpty) return 'Escribe el nombre del producto.';
    if (_categoryId == null) return 'Selecciona una categoría.';
    if (!_editing) {
      if (_warehouseId == null) return 'Selecciona un almacén.';
      final stock = num.tryParse(_stock.text.trim().isEmpty ? '0' : _stock.text.trim());
      if (stock == null || !_unit.accepts(stock, allowZero: true)) {
        return stock != null && stock < 0 ? 'La cantidad debe ser igual o mayor a cero.' : _unit.precisionMessage;
      }
      if (_withLot && _lotNumber.text.trim().isEmpty) return 'Escribe el número de lote o desactiva "Asignar lote".';
    }
    if (_withPrices) {
      for (final c in [_purchasePrice, _salePrice]) {
        final value = num.tryParse(c.text.trim().isEmpty ? '0' : c.text.trim());
        if (value == null || value < 0) return 'Los precios deben ser iguales o mayores a cero.';
      }
    }
    return null;
  }

  Future<void> _save() async {
    final message = _validate();
    if (message != null) {
      setState(() => _error = message);
      return;
    }
    setState(() {
      _saving = true;
      _error = null;
    });
    String price(TextEditingController c) => _withPrices ? (c.text.trim().isEmpty ? '0' : c.text.trim()) : '0';
    final values = <String, String>{
      'name': _name.text.trim(),
      'description': _description.text.trim(),
      'category_id': '$_categoryId',
      'supplier_id': _supplierId?.toString() ?? '',
      if (!_editing || _withPrices) 'purchase_price': price(_purchasePrice),
      if (!_editing || _withPrices) 'sale_price': price(_salePrice),
      'barcode': _withBarcodes ? _barcode.text.trim() : '',
      'sale_barcode': _withBarcodes ? _saleBarcode.text.trim() : '',
      'sat_product_code': _withBilling ? _satProduct.text.trim() : '',
      'sat_unit_code': _withBilling ? _satUnit.text.trim() : '',
      if (!_editing) ...{
        'stock': _stock.text.trim().isEmpty ? '0' : _stock.text.trim(),
        'base_unit': _baseUnit,
        'warehouse_id': '$_warehouseId',
        'tracks_lots': _withLot ? 'true' : 'false',
        if (_withLot) 'initial_lot_number': _lotNumber.text.trim(),
        if (_withLot && _lotExpiration != null) 'initial_expiration_date': _lotExpiration!,
      },
      if (_editing && _edit?['base_unit_locked'] != true) 'base_unit': _baseUnit,
    };
    final fields = [
      for (final entry in values.entries) MapEntry('product[${entry.key}]', entry.value),
      for (final id in _removedImages) MapEntry('product[removed_images][]', '$id'),
    ];
    final files = [
      for (final image in _newImages) MapEntry(_editing ? 'product[new_images][]' : 'product[images][]', image.path),
    ];
    try {
      final api = context.read<ApiClient>();
      final result = _editing
          ? await api.multipart('PUT', '/products/${_edit!['id']}', fields: fields, files: files)
          : await api.multipart('POST', '/products', fields: fields, files: files);
      if (mounted) Navigator.pop(context, asMap(result));
    } catch (error) {
      if (mounted) setState(() => _error = error.toString());
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    Widget body;
    if (_loading) {
      body = LoadingView(label: _editing ? 'Cargando…' : 'Preparando categoría y almacén…');
    } else if (_loadError != null) {
      body = ErrorView(error: _loadError!, onRetry: _loadCatalogs);
    } else {
      final existingImages = asMapList(_edit?['image_urls']).where((i) => !_removedImages.contains((i['id'] as num).toInt())).toList();
      body = Form(
        key: _form,
        child: ListView(padding: const EdgeInsets.fromLTRB(16, 16, 16, 120), children: [
          if (_error != null) ...[
            Card(
              color: theme.colorScheme.errorContainer,
              child: Padding(padding: const EdgeInsets.all(12), child: Text(_error!, style: TextStyle(color: theme.colorScheme.onErrorContainer))),
            ),
            const SizedBox(height: 12),
          ],
          Text('Datos básicos', style: theme.textTheme.titleMedium),
          const SizedBox(height: 12),
          TextFormField(controller: _name, textCapitalization: TextCapitalization.sentences, decoration: const InputDecoration(labelText: 'Nombre *', hintText: 'Ej. Café molido de 250 g')),
          const SizedBox(height: 12),
          RecordDropdown(label: 'Categoría *', records: _categories, value: _categoryId, icon: Icons.category_outlined, onChanged: (v) => setState(() => _categoryId = v)),
          if (!_editing) ...[
            const SizedBox(height: 12),
            RecordDropdown(label: 'Almacén *', records: _warehouses, value: _warehouseId, icon: Icons.warehouse_outlined, onChanged: (v) => setState(() => _warehouseId = v)),
          ],
          const SizedBox(height: 12),
          Row(children: [
            if (!_editing)
              Expanded(
                child: TextFormField(
                  controller: _stock,
                  keyboardType: const TextInputType.numberWithOptions(decimal: true),
                  decoration: const InputDecoration(labelText: 'Cantidad inicial'),
                ),
              ),
            if (!_editing) const SizedBox(width: 12),
            Expanded(
              child: DropdownButtonFormField<String>(
                initialValue: _units.any((u) => u.code == _baseUnit) ? _baseUnit : null,
                isExpanded: true,
                decoration: InputDecoration(
                  labelText: 'Unidad',
                  helperText: _edit?['base_unit_locked'] == true ? 'Ya tiene movimientos' : null,
                ),
                items: [for (final u in _units) DropdownMenuItem(value: u.code, child: Text('${u.name} (${u.symbol})'))],
                onChanged: _edit?['base_unit_locked'] == true ? null : (v) => setState(() => _baseUnit = v ?? 'pz'),
              ),
            ),
          ]),
          const SizedBox(height: 12),
          RecordDropdown(
            label: 'Proveedor',
            records: _suppliers,
            value: _supplierId,
            emptyLabel: 'Sin proveedor',
            icon: Icons.local_shipping_outlined,
            onChanged: (v) => setState(() => _supplierId = v),
          ),
          const SizedBox(height: 12),
          TextFormField(controller: _description, maxLines: 3, decoration: const InputDecoration(labelText: 'Notas', hintText: 'Agrega alguna nota sobre este producto')),
          const SizedBox(height: 20),
          Text('Datos opcionales', style: theme.textTheme.titleMedium),
          SwitchListTile(contentPadding: EdgeInsets.zero, title: const Text('Códigos de barras'), value: _withBarcodes, onChanged: (v) => setState(() => _withBarcodes = v)),
          if (_withBarcodes) ...[
            _BarcodeField(controller: _barcode, label: 'Código de compra', onScan: () => _scanInto(_barcode)),
            const SizedBox(height: 12),
            _BarcodeField(controller: _saleBarcode, label: 'Código de venta', onScan: () => _scanInto(_saleBarcode)),
          ],
          SwitchListTile(contentPadding: EdgeInsets.zero, title: const Text('Precios'), value: _withPrices, onChanged: (v) => setState(() => _withPrices = v)),
          if (_withPrices)
            Row(children: [
              Expanded(child: _MoneyField(controller: _purchasePrice, label: 'Precio de compra')),
              const SizedBox(width: 12),
              Expanded(child: _MoneyField(controller: _salePrice, label: 'Precio de venta')),
            ]),
          SwitchListTile(contentPadding: EdgeInsets.zero, title: const Text('Datos de facturación'), value: _withBilling, onChanged: (v) => setState(() => _withBilling = v)),
          if (_withBilling)
            Row(children: [
              Expanded(child: TextFormField(controller: _satProduct, decoration: const InputDecoration(labelText: 'Clave SAT producto', hintText: '01010101'))),
              const SizedBox(width: 12),
              Expanded(child: TextFormField(controller: _satUnit, decoration: const InputDecoration(labelText: 'Clave SAT unidad', hintText: 'H87'))),
            ]),
          if (!_editing) ...[
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('Asignar lote'),
              subtitle: const Text('Controla lotes y caducidades de este producto'),
              value: _withLot,
              onChanged: (v) => setState(() => _withLot = v),
            ),
            if (_withLot) ...[
              TextFormField(controller: _lotNumber, decoration: const InputDecoration(labelText: 'Número de lote *')),
              const SizedBox(height: 12),
              DateField(label: 'Caducidad', value: _lotExpiration, clearable: true, onChanged: (v) => setState(() => _lotExpiration = v)),
            ],
          ],
          const SizedBox(height: 20),
          Text('Fotos', style: theme.textTheme.titleMedium),
          const SizedBox(height: 8),
          Wrap(spacing: 8, runSpacing: 8, children: [
            for (final image in existingImages)
              _Thumb(
                image: Image.network(image['url'].toString(), fit: BoxFit.cover, errorBuilder: (_, _, _) => const Icon(Icons.broken_image_outlined)),
                onRemove: () => setState(() => _removedImages.add((image['id'] as num).toInt())),
              ),
            for (final file in _newImages)
              _Thumb(image: Image.file(File(file.path), fit: BoxFit.cover, cacheWidth: 240), onRemove: () => setState(() => _newImages.remove(file))),
            OutlinedButton.icon(onPressed: () => _addImage(ImageSource.camera), icon: const Icon(Icons.photo_camera_outlined), label: const Text('Cámara')),
            OutlinedButton.icon(onPressed: () => _addImage(ImageSource.gallery), icon: const Icon(Icons.photo_library_outlined), label: const Text('Galería')),
          ]),
          if (!_editing)
            Padding(
              padding: const EdgeInsets.only(top: 16),
              child: Text('* Campos obligatorios. La cantidad puede ser cero.', style: theme.textTheme.bodySmall),
            ),
        ]),
      );
    }
    return Scaffold(
      appBar: AppBar(title: Text(_editing ? 'Editar producto' : 'Crear producto')),
      body: body,
      bottomNavigationBar: _loading || _loadError != null
          ? null
          : SafeArea(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: FilledButton(onPressed: _saving ? null : _save, child: Text(_saving ? 'Guardando…' : 'Guardar')),
              ),
            ),
    );
  }
}

class _BarcodeField extends StatelessWidget {
  const _BarcodeField({required this.controller, required this.label, required this.onScan});
  final TextEditingController controller;
  final String label;
  final VoidCallback onScan;

  @override
  Widget build(BuildContext context) => TextFormField(
        controller: controller,
        decoration: InputDecoration(
          labelText: label,
          suffixIcon: IconButton(tooltip: 'Escanear', icon: const Icon(Icons.qr_code_scanner), onPressed: onScan),
        ),
      );
}

class _MoneyField extends StatelessWidget {
  const _MoneyField({required this.controller, required this.label});
  final TextEditingController controller;
  final String label;

  @override
  Widget build(BuildContext context) => TextFormField(
        controller: controller,
        keyboardType: const TextInputType.numberWithOptions(decimal: true),
        decoration: InputDecoration(labelText: label, prefixText: r'$ '),
      );
}

class _Thumb extends StatelessWidget {
  const _Thumb({required this.image, required this.onRemove});
  final Widget image;
  final VoidCallback onRemove;

  @override
  Widget build(BuildContext context) => SizedBox(
        width: 88,
        height: 88,
        child: Stack(fit: StackFit.expand, children: [
          ClipRRect(
            borderRadius: BorderRadius.circular(10),
            child: image,
          ),
          Positioned(
            top: 2,
            right: 2,
            child: IconButton.filledTonal(
              visualDensity: VisualDensity.compact,
              tooltip: 'Quitar foto',
              iconSize: 16,
              onPressed: onRemove,
              icon: const Icon(Icons.close),
            ),
          ),
        ]),
      );
}
