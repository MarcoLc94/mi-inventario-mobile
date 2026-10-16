import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../core/api_client.dart';
import '../core/formatters.dart';
import '../core/user_profile.dart';
import 'barcode_scanner.dart';

/// Buscador de productos en hoja inferior, con escáner de código de barras.
/// Con [warehouseId] solo muestra productos con existencias en ese almacén
/// (GET /warehouses/:id/products) y el stock mostrado es el de ese almacén.
Future<Map<String, dynamic>?> pickProduct(BuildContext context, {int? warehouseId, String title = 'Elegir producto'}) {
  return showModalBottomSheet<Map<String, dynamic>>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    builder: (_) => _ProductPicker(warehouseId: warehouseId, title: title),
  );
}

class _ProductPicker extends StatefulWidget {
  const _ProductPicker({this.warehouseId, required this.title});
  final int? warehouseId;
  final String title;

  @override
  State<_ProductPicker> createState() => _ProductPickerState();
}

class _ProductPickerState extends State<_ProductPicker> {
  final _search = TextEditingController();
  Timer? _debounce;
  List<Map<String, dynamic>> _items = [];
  bool _loading = false;
  Object? _error;
  int _request = 0;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _search.dispose();
    super.dispose();
  }

  Future<List<Map<String, dynamic>>> _query(String text) async {
    final api = context.read<ApiClient>();
    if (widget.warehouseId != null) {
      return asMapList(await api.get('/warehouses/${widget.warehouseId}/products', query: {'name': text}));
    }
    final isCode = RegExp(r'^\d{4,}$').hasMatch(text);
    final page = PageResult.fromJson(await api.get('/products', query: {
      'page': 1,
      'per_page': 40,
      'sort_by': 'name',
      'sort_dir': 'asc',
      if (text.isNotEmpty) (isCode ? 'barcode' : 'name'): text,
    }));
    var items = page.items;
    // Un código de venta no coincide con barcode: se intenta también ese campo.
    if (isCode && items.isEmpty) {
      items = PageResult.fromJson(await api.get('/products', query: {'page': 1, 'per_page': 40, 'sale_barcode': text})).items;
    }
    return items;
  }

  Future<List<Map<String, dynamic>>> _load({bool exactPick = false}) async {
    final request = ++_request;
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final items = await _query(_search.text.trim());
      if (!mounted || request != _request) return items;
      setState(() => _items = items);
      return items;
    } catch (error) {
      if (mounted && request == _request) setState(() => _error = error);
      return const [];
    } finally {
      if (mounted && request == _request) setState(() => _loading = false);
    }
  }

  Future<void> _scan() async {
    final code = await scanBarcode(context);
    if (code == null || !mounted) return;
    _search.text = code;
    final items = await _load();
    if (items.length == 1 && mounted) Navigator.pop(context, items.first);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
      child: SizedBox(
        height: MediaQuery.of(context).size.height * .85,
        child: Column(children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 16, 8, 8),
            child: Row(children: [
              Expanded(child: Text(widget.title, style: theme.textTheme.titleMedium)),
              IconButton(tooltip: 'Cerrar', onPressed: () => Navigator.pop(context), icon: const Icon(Icons.close)),
            ]),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: TextField(
              controller: _search,
              autofocus: true,
              onChanged: (_) {
                _debounce?.cancel();
                _debounce = Timer(const Duration(milliseconds: 350), _load);
              },
              decoration: InputDecoration(
                hintText: 'Nombre o código de barras',
                prefixIcon: const Icon(Icons.search),
                suffixIcon: IconButton(tooltip: 'Escanear código', icon: const Icon(Icons.qr_code_scanner), onPressed: _scan),
              ),
            ),
          ),
          if (_loading) const LinearProgressIndicator(minHeight: 2),
          Expanded(
            child: _error != null
                ? Center(child: Text(_error.toString(), textAlign: TextAlign.center))
                : _items.isEmpty && !_loading
                    ? const Center(child: Text('Sin resultados'))
                    : ListView.builder(
                        itemCount: _items.length,
                        itemBuilder: (context, i) {
                          final p = _items[i];
                          return ListTile(
                            title: Text(p['name']?.toString() ?? ''),
                            subtitle: Text([
                              if (p['barcode'] != null) p['barcode'].toString(),
                              if (asMap(p['category'])['name'] != null) asMap(p['category'])['name'].toString(),
                            ].join(' · ')),
                            trailing: Text('${formatNumber(p['available_stock'] ?? p['stock'])} ${p['base_unit'] ?? ''}'),
                            onTap: () => Navigator.pop(context, p),
                          );
                        },
                      ),
          ),
        ]),
      ),
    );
  }
}
