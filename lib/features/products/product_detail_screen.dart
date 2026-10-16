import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../../core/api_client.dart';
import '../../core/formatters.dart';
import '../../core/user_profile.dart';
import '../../widgets/async_states.dart';
import '../../widgets/form_fields.dart';
import '../home/dashboard_data.dart';
import '../lots/lot_widgets.dart';
import 'product_form_screen.dart';

class ProductDetailScreen extends StatefulWidget {
  const ProductDetailScreen({super.key, required this.id});
  final String id;

  @override
  State<ProductDetailScreen> createState() => _ProductDetailScreenState();
}

class _ProductDetailScreenState extends State<ProductDetailScreen> {
  late Future<Map<String, dynamic>> _future = _load();
  Map<String, dynamic>? _product;

  Future<Map<String, dynamic>> _load() async {
    final product = asMap(await context.read<ApiClient>().get('/products/${widget.id}'));
    _product = product;
    return product;
  }

  Future<void> _reload() async {
    final next = _load();
    setState(() => _future = next);
    await next;
  }

  Future<void> _edit() async {
    final product = _product;
    if (product == null) return;
    final saved = await Navigator.of(context).push<Map<String, dynamic>>(
      MaterialPageRoute(builder: (_) => ProductFormScreen(product: product)),
    );
    if (saved != null && mounted) {
      showMessage(context, 'Producto actualizado');
      await _reload();
    }
  }

  Future<void> _delete() async {
    final ok = await confirm(context,
        title: 'Eliminar producto', message: '¿Seguro que deseas eliminar "${_product?['name']}"? Esta acción no se puede deshacer.', action: 'Eliminar', destructive: true);
    if (!ok || !mounted) return;
    try {
      await context.read<ApiClient>().delete('/products/${widget.id}');
      if (!mounted) return;
      showMessage(context, 'Producto eliminado');
      context.pop(true);
    } catch (error) {
      if (mounted) showError(context, error);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Producto'),
        actions: [
          IconButton(tooltip: 'Editar', onPressed: _product == null ? null : _edit, icon: const Icon(Icons.edit_outlined)),
          PopupMenuButton<String>(
            onSelected: (value) => value == 'delete' ? _delete() : null,
            itemBuilder: (_) => const [PopupMenuItem(value: 'delete', child: Text('Eliminar producto'))],
          ),
        ],
      ),
      body: FutureBuilder<Map<String, dynamic>>(
        future: _future,
        builder: (context, snapshot) {
          if (snapshot.connectionState != ConnectionState.done && _product == null) return const LoadingView();
          if (snapshot.hasError) return ErrorView(error: snapshot.error!, onRetry: _reload);
          return RefreshIndicator(onRefresh: _reload, child: _ProductDetail(product: snapshot.data ?? _product!, onChanged: _reload));
        },
      ),
    );
  }
}

class _ProductDetail extends StatelessWidget {
  const _ProductDetail({required this.product, required this.onChanged});
  final Map<String, dynamic> product;
  final Future<void> Function() onChanged;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final images = asMapList(product['image_urls']);
    final warehouses = asMapList(product['stock_by_warehouse']);
    final movements = asMapList(product['stock_movements']);
    final state = stockState(product);

    return ListView(padding: const EdgeInsets.all(16), children: [
      if (images.isNotEmpty) ...[
        SizedBox(
          height: 180,
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            itemCount: images.length,
            separatorBuilder: (_, _) => const SizedBox(width: 8),
            itemBuilder: (_, i) => ClipRRect(
              borderRadius: BorderRadius.circular(12),
              child: Image.network(images[i]['url'].toString(), height: 180, fit: BoxFit.cover,
                  errorBuilder: (_, _, _) => const SizedBox(width: 180, child: Icon(Icons.broken_image_outlined))),
            ),
          ),
        ),
        const SizedBox(height: 16),
      ],
      Text(product['name']?.toString() ?? '', style: theme.textTheme.headlineSmall),
      if ((product['description']?.toString() ?? '').isNotEmpty) ...[
        const SizedBox(height: 4),
        Text(product['description'].toString(), style: theme.textTheme.bodyMedium),
      ],
      const SizedBox(height: 16),
      Card(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Row(children: [
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text('Existencias', style: theme.textTheme.bodySmall),
                Text('${formatNumber(product['stock'])} ${product['base_unit'] ?? ''}',
                    style: theme.textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w700)),
                Text(stockLabels[state]!, style: theme.textTheme.bodySmall),
              ]),
            ),
            Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
              Text('Venta', style: theme.textTheme.bodySmall),
              Text(formatMoney(product['sale_price']), style: theme.textTheme.titleMedium),
              const SizedBox(height: 4),
              Text('Compra', style: theme.textTheme.bodySmall),
              Text(formatMoney(product['purchase_price']), style: theme.textTheme.titleSmall),
            ]),
          ]),
        ),
      ),
      const SizedBox(height: 12),
      SectionCard(title: 'Datos', children: [
        InfoRow('Categoría', asMap(product['category'])['name']?.toString()),
        InfoRow('Proveedor', asMap(product['supplier'])['name']?.toString()),
        InfoRow('Código de compra', product['barcode']?.toString()),
        InfoRow('Código de venta', product['sale_barcode']?.toString()),
        InfoRow('Clave SAT', product['sat_product_code']?.toString()),
        InfoRow('Unidad SAT', product['sat_unit_code']?.toString()),
        InfoRow('Registrado por', asMap(product['created_by'])['name']?.toString()),
      ]),
      if (warehouses.isNotEmpty) ...[
        const SizedBox(height: 12),
        SectionCard(title: 'Existencias por almacén', children: [
          for (final w in warehouses)
            ListTile(
              dense: true,
              leading: const Icon(Icons.warehouse_outlined),
              title: Text(w['warehouse_name']?.toString() ?? ''),
              subtitle: Text([
                'Disponible ${formatNumber(w['available_stock'])}',
                if ((toNum(w['reserved_stock']) ?? 0) > 0) 'Reservado ${formatNumber(w['reserved_stock'])}',
                if (w['location_code'] != null) 'Ubicación ${w['location_code']}',
              ].join(' · ')),
              trailing: Text(formatNumber(w['stock']), style: theme.textTheme.titleMedium),
            ),
        ]),
      ],
      const SizedBox(height: 12),
      _Presentations(product: product, onChanged: onChanged),
      const SizedBox(height: 12),
      ProductLotsCard(product: product, onChanged: onChanged),
      if (movements.isNotEmpty) ...[
        const SizedBox(height: 12),
        SectionCard(title: 'Últimos movimientos', children: [
          for (final m in movements.take(15))
            Builder(builder: (context) {
              final entry = m['movement_type'] == 'IN';
              final color = entry ? Colors.green.shade700 : theme.colorScheme.error;
              return ListTile(
                dense: true,
                leading: Icon(entry ? Icons.south_west : Icons.north_east, color: color),
                title: Text(entry ? 'Entrada' : 'Salida'),
                subtitle: Text([
                  formatDateTime(m['created_at']),
                  if (asMap(m['warehouse'])['name'] != null) asMap(m['warehouse'])['name'],
                  if ((m['notes']?.toString() ?? '').isNotEmpty) m['notes'],
                ].join(' · ')),
                trailing: Text('${entry ? '+' : '-'}${formatNumber(m['quantity'])}', style: theme.textTheme.titleSmall?.copyWith(color: color)),
              );
            }),
        ]),
      ],
      const SizedBox(height: 24),
    ]);
  }
}

/// Presentaciones (caja, paquete…) con su factor sobre la unidad base.
class _Presentations extends StatelessWidget {
  const _Presentations({required this.product, required this.onChanged});
  final Map<String, dynamic> product;
  final Future<void> Function() onChanged;

  static int? _customId(Map<String, dynamic> p) {
    final ref = p['ref']?.toString() ?? '';
    return ref.startsWith('pu:') ? int.tryParse(ref.substring(3)) : null;
  }

  Future<void> _openForm(BuildContext context, [Map<String, dynamic>? presentation]) async {
    final saved = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (_) => _PresentationForm(product: product, presentation: presentation, id: presentation == null ? null : _customId(presentation)),
    );
    if (saved == true) await onChanged();
  }

  Future<void> _delete(BuildContext context, Map<String, dynamic> presentation) async {
    final ok = await confirm(context, title: 'Eliminar presentación', message: '¿Eliminar "${presentation['name']}"?', action: 'Eliminar', destructive: true);
    if (!ok || !context.mounted) return;
    try {
      await context.read<ApiClient>().delete('/products/${product['id']}/presentations/${_customId(presentation)}');
      await onChanged();
    } catch (error) {
      if (context.mounted) showError(context, error);
    }
  }

  @override
  Widget build(BuildContext context) {
    final presentations = asMapList(product['presentations']).where((p) => p['ref'] != 'base').toList();
    return SectionCard(
      title: 'Presentaciones',
      trailing: TextButton.icon(onPressed: () => _openForm(context), icon: const Icon(Icons.add, size: 18), label: const Text('Agregar')),
      children: [
        if (presentations.isEmpty)
          const Padding(padding: EdgeInsets.fromLTRB(16, 0, 16, 8), child: Text('Vende o compra por caja, paquete u otra presentación.')),
        for (final p in presentations)
          ListTile(
            dense: true,
            title: Text(p['name']?.toString() ?? ''),
            subtitle: Text('${formatNumber(p['factor'])} ${product['base_unit'] ?? ''} · venta ${formatMoney(p['sale_price'])}'),
            trailing: _customId(p) == null
                ? null
                : PopupMenuButton<String>(
                    onSelected: (v) => v == 'edit' ? _openForm(context, p) : _delete(context, p),
                    itemBuilder: (_) => const [
                      PopupMenuItem(value: 'edit', child: Text('Editar')),
                      PopupMenuItem(value: 'delete', child: Text('Eliminar')),
                    ],
                  ),
          ),
      ],
    );
  }
}

class _PresentationForm extends StatefulWidget {
  const _PresentationForm({required this.product, this.presentation, this.id});
  final Map<String, dynamic> product;
  final Map<String, dynamic>? presentation;
  final int? id;

  @override
  State<_PresentationForm> createState() => _PresentationFormState();
}

class _PresentationFormState extends State<_PresentationForm> {
  late final _name = TextEditingController(text: widget.presentation?['name']?.toString());
  late final _factor = TextEditingController(text: widget.presentation?['factor']?.toString());
  late final _barcode = TextEditingController(text: widget.presentation?['barcode']?.toString());
  late final _sale = TextEditingController(text: widget.presentation?['sale_price']?.toString());
  late final _purchase = TextEditingController(text: widget.presentation?['purchase_price']?.toString());
  bool _saving = false;
  String? _error;

  Future<void> _save() async {
    final factor = num.tryParse(_factor.text.trim());
    if (_name.text.trim().isEmpty || factor == null || factor <= 0) {
      setState(() => _error = 'Escribe el nombre y cuántas unidades base contiene la presentación.');
      return;
    }
    num? price(TextEditingController c) => c.text.trim().isEmpty ? null : num.tryParse(c.text.trim());
    final body = {
      'product_unit': {
        'name': _name.text.trim(),
        'factor': factor,
        'barcode': _barcode.text.trim().isEmpty ? null : _barcode.text.trim(),
        'sale_price': price(_sale),
        'purchase_price': price(_purchase),
      },
    };
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      final api = context.read<ApiClient>();
      final base = '/products/${widget.product['id']}/presentations';
      widget.id == null ? await api.post(base, body) : await api.patch('$base/${widget.id}', body);
      if (mounted) Navigator.pop(context, true);
    } catch (error) {
      if (mounted) setState(() => _error = error.toString());
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) => Padding(
        padding: EdgeInsets.fromLTRB(16, 16, 16, MediaQuery.of(context).viewInsets.bottom + 16),
        child: SingleChildScrollView(
          child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            Text(widget.id == null ? 'Agregar presentación' : 'Editar presentación', style: Theme.of(context).textTheme.titleLarge),
            const SizedBox(height: 12),
            if (_error != null) Text(_error!, style: TextStyle(color: Theme.of(context).colorScheme.error)),
            TextField(controller: _name, decoration: const InputDecoration(labelText: 'Nombre *', hintText: 'Ej. Caja con 12')),
            const SizedBox(height: 12),
            TextField(
              controller: _factor,
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              decoration: InputDecoration(labelText: 'Contiene (${widget.product['base_unit'] ?? 'pz'}) *'),
            ),
            const SizedBox(height: 12),
            TextField(controller: _barcode, decoration: const InputDecoration(labelText: 'Código de barras')),
            const SizedBox(height: 12),
            Row(children: [
              Expanded(child: TextField(controller: _purchase, keyboardType: const TextInputType.numberWithOptions(decimal: true), decoration: const InputDecoration(labelText: 'Precio compra', prefixText: r'$ '))),
              const SizedBox(width: 12),
              Expanded(child: TextField(controller: _sale, keyboardType: const TextInputType.numberWithOptions(decimal: true), decoration: const InputDecoration(labelText: 'Precio venta', prefixText: r'$ '))),
            ]),
            const SizedBox(height: 4),
            Text('Sin precio, se calcula con el de la unidad base.', style: Theme.of(context).textTheme.bodySmall),
            const SizedBox(height: 16),
            FilledButton(onPressed: _saving ? null : _save, child: Text(_saving ? 'Guardando…' : 'Guardar')),
          ]),
        ),
      );
}
