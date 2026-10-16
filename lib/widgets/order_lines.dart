import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../core/catalogs.dart';
import '../core/formatters.dart';
import '../core/user_profile.dart';
import 'form_fields.dart';
import 'product_picker.dart';

/// Partida de una orden de compra o de venta. La cantidad y el precio se
/// capturan en la presentación elegida; el backend convierte a unidad base
/// con `presentation` + `presentation_quantity` (igual que la web).
class OrderLine {
  OrderLine({required this.product, required this.unit, this.id, this.warehouseId, num? quantity, num? price, this.presentation = 'base'})
      : quantity = TextEditingController(text: quantity == null ? '' : formatPlain(quantity)),
        price = TextEditingController(text: price == null ? '' : formatPlain(price));

  /// Partida existente al editar (para enviar `id` / `_destroy`).
  final int? id;
  final Map<String, dynamic> product;
  final Unit unit;
  int? warehouseId;
  String presentation;
  final TextEditingController quantity;
  final TextEditingController price;

  num get quantityValue => num.tryParse(quantity.text.trim()) ?? 0;
  num get priceValue => num.tryParse(price.text.trim()) ?? 0;
  num get total => quantityValue * priceValue;

  List<Map<String, dynamic>> get presentations => asMapList(product['presentations']).where((p) => p['ref'] != 'base').toList();
  num get factor => toNum(presentations.where((p) => p['ref'] == presentation).firstOrNull?['factor']) ?? 1;
  num get baseQuantity => quantityValue * factor;

  void dispose() {
    quantity.dispose();
    price.dispose();
  }
}

/// `unit_type` heredado que validan las partidas (unit, kg, lt), igual que la web.
String legacyUnitType(String? code) => switch (code) { 'kg' => 'kg', 'l' => 'lt', _ => 'unit' };

String formatPlain(num value) => value == value.roundToDouble() ? value.toInt().toString() : value.toString();

/// Subtotal, IVA y total de un conjunto de partidas.
({num subtotal, num iva, num total}) orderAmounts(List<OrderLine> lines, num ivaRate) {
  final subtotal = lines.fold<num>(0, (sum, line) => sum + line.total);
  final iva = subtotal * ivaRate;
  return (subtotal: subtotal, iva: iva, total: subtotal + iva);
}

/// Mensaje del primer problema en las partidas, o null si todo está bien.
String? orderLinesError(List<OrderLine> lines, {bool requireWarehouse = true}) {
  if (lines.isEmpty) return 'Agrega al menos un producto.';
  for (final line in lines) {
    final name = line.product['name'];
    if (line.quantityValue <= 0) return '$name: la cantidad debe ser mayor que cero.';
    if (!line.unit.accepts(line.baseQuantity)) return '$name: ${line.unit.precisionMessage}';
    if (line.priceValue < 0) return '$name: el precio no puede ser negativo.';
    if (requireWarehouse && line.warehouseId == null) return '$name: elige el almacén.';
  }
  return null;
}

/// Editor de partidas con selector de producto (y escáner), almacén,
/// presentación, cantidad y precio.
class OrderLinesEditor extends StatefulWidget {
  const OrderLinesEditor({super.key, required this.lines, required this.warehouses, required this.priceKey, required this.onChanged, this.defaultWarehouseId});

  final List<OrderLine> lines;
  final List<Map<String, dynamic>> warehouses;

  /// `purchase_price` para compras, `sale_price` para ventas.
  final String priceKey;
  final int? defaultWarehouseId;
  final VoidCallback onChanged;

  @override
  State<OrderLinesEditor> createState() => _OrderLinesEditorState();
}

class _OrderLinesEditorState extends State<OrderLinesEditor> {
  Future<void> _add() async {
    final picked = await pickProduct(context);
    if (picked == null || !mounted) return;
    final unit = await context.read<Catalogs>().unit(picked['base_unit']?.toString());
    widget.lines.add(OrderLine(
      product: picked,
      unit: unit,
      warehouseId: (picked['warehouse_id'] as num?)?.toInt() ?? widget.defaultWarehouseId,
      price: toNum(picked[widget.priceKey]),
    ));
    widget.onChanged();
  }

  void _setPresentation(OrderLine line, String ref) {
    final presentation = line.presentations.where((p) => p['ref'] == ref).firstOrNull;
    line.presentation = ref;
    final price = ref == 'base' ? toNum(line.product[widget.priceKey]) : toNum(presentation?[widget.priceKey]);
    if (price != null) line.price.text = formatPlain(price);
    widget.onChanged();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      for (final line in widget.lines)
        Card(
          margin: const EdgeInsets.only(bottom: 8),
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              Row(children: [
                Expanded(child: Text(line.product['name']?.toString() ?? '', style: theme.textTheme.titleSmall)),
                IconButton(
                  tooltip: 'Quitar',
                  icon: const Icon(Icons.delete_outline),
                  onPressed: () {
                    widget.lines.remove(line);
                    widget.onChanged();
                  },
                ),
              ]),
              if (widget.warehouses.length > 1) ...[
                RecordDropdown(
                  label: 'Almacén',
                  records: widget.warehouses,
                  value: line.warehouseId,
                  onChanged: (v) {
                    line.warehouseId = v;
                    widget.onChanged();
                  },
                ),
                const SizedBox(height: 8),
              ],
              if (line.presentations.isNotEmpty) ...[
                DropdownButtonFormField<String>(
                  initialValue: line.presentation,
                  isExpanded: true,
                  decoration: const InputDecoration(labelText: 'Presentación'),
                  items: [
                    DropdownMenuItem(value: 'base', child: Text(line.unit.name)),
                    for (final p in line.presentations) DropdownMenuItem(value: p['ref'].toString(), child: Text(p['name'].toString())),
                  ],
                  onChanged: (v) => _setPresentation(line, v ?? 'base'),
                ),
                const SizedBox(height: 8),
              ],
              Row(children: [
                Expanded(
                  child: TextField(
                    controller: line.quantity,
                    keyboardType: const TextInputType.numberWithOptions(decimal: true),
                    decoration: InputDecoration(labelText: 'Cantidad', suffixText: line.presentation == 'base' ? line.unit.symbol : null),
                    onChanged: (_) => widget.onChanged(),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: TextField(
                    controller: line.price,
                    keyboardType: const TextInputType.numberWithOptions(decimal: true),
                    decoration: const InputDecoration(labelText: 'Precio unitario', prefixText: r'$ '),
                    onChanged: (_) => widget.onChanged(),
                  ),
                ),
              ]),
              const SizedBox(height: 4),
              Align(
                alignment: Alignment.centerRight,
                child: Text(
                  [if (line.presentation != 'base') '= ${line.unit.format(line.baseQuantity)}', 'Importe ${formatMoney(line.total)}'].join(' · '),
                  style: theme.textTheme.bodySmall,
                ),
              ),
            ]),
          ),
        ),
      OutlinedButton.icon(onPressed: _add, icon: const Icon(Icons.add), label: const Text('Agregar producto')),
    ]);
  }
}

/// Resumen de importes con selector de tasa de IVA.
class AmountsCard extends StatelessWidget {
  const AmountsCard({super.key, required this.lines, required this.ivaRate, required this.onIvaChanged, this.currency = 'MXN'});
  final List<OrderLine> lines;
  final num ivaRate;
  final ValueChanged<num> onIvaChanged;
  final String currency;

  @override
  Widget build(BuildContext context) {
    final amounts = orderAmounts(lines, ivaRate);
    final theme = Theme.of(context);
    return SectionCard(title: 'Importes', children: [
      Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16),
        child: DropdownButtonFormField<num>(
          initialValue: const [0, 0.08, 0.16].contains(ivaRate) ? ivaRate : 0.16,
          decoration: const InputDecoration(labelText: 'IVA'),
          items: const [
            DropdownMenuItem(value: 0.16, child: Text('16 %')),
            DropdownMenuItem(value: 0.08, child: Text('8 % (frontera)')),
            DropdownMenuItem(value: 0, child: Text('0 % / exento')),
          ],
          onChanged: (v) => onIvaChanged(v ?? 0.16),
        ),
      ),
      const SizedBox(height: 8),
      InfoRow('Subtotal', formatMoney(amounts.subtotal)),
      InfoRow('IVA', formatMoney(amounts.iva)),
      Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
        child: Row(children: [
          const Expanded(child: Text('Total')),
          Text('${formatMoney(amounts.total)} $currency', style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700)),
        ]),
      ),
    ]);
  }
}

/// Partidas de un documento ya guardado (solo lectura).
class DocumentLines extends StatelessWidget {
  const DocumentLines({super.key, required this.items, this.title = 'Productos', this.trailing});
  final List<Map<String, dynamic>> items;
  final String title;
  final String Function(Map<String, dynamic> item)? trailing;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return SectionCard(title: title, children: [
      for (final item in items)
        ListTile(
          dense: true,
          title: Text(asMap(item['product'])['name']?.toString() ?? item['description']?.toString() ?? item['service_description']?.toString() ?? 'Producto'),
          subtitle: Text([
            item['presentation_name'] != null
                ? '${formatNumber(item['presentation_quantity'])} ${item['presentation_name']}'
                : '${formatNumber(item['quantity'])} ${asMap(item['product'])['base_unit'] ?? ''}',
            if (item['unit_price'] != null) '× ${formatMoney(item['presentation_unit_price'] ?? item['unit_price'])}',
            if (asMap(item['warehouse'])['name'] != null) asMap(item['warehouse'])['name'],
          ].join(' · ')),
          trailing: Text(trailing?.call(item) ?? formatMoney(item['total_price'] ?? item['subtotal'] ?? (toNum(item['quantity']) ?? 0) * (toNum(item['unit_price']) ?? 0)),
              style: theme.textTheme.titleSmall),
        ),
    ]);
  }
}
