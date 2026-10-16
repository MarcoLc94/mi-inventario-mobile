import 'dart:async';

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../../core/api_client.dart';
import '../../core/formatters.dart';
import '../../core/user_profile.dart';
import '../../widgets/app_shell.dart';
import '../../widgets/async_states.dart';
import '../../widgets/barcode_scanner.dart';
import '../home/dashboard_data.dart';
import 'product_form_screen.dart';

/// Catálogo de productos: búsqueda por nombre o código, filtro por categoría
/// y por estado de existencias, con carga por páginas.
class ProductsScreen extends StatefulWidget {
  const ProductsScreen({super.key, this.initialFilter});
  final String? initialFilter;

  @override
  State<ProductsScreen> createState() => _ProductsScreenState();
}

class _ProductsScreenState extends State<ProductsScreen> {
  static const _perPage = 30;
  final _scroll = ScrollController();
  final _search = TextEditingController();
  Timer? _debounce;
  final _items = <Map<String, dynamic>>[];
  List<Map<String, dynamic>> _categories = [];
  int? _categoryId;
  late bool _onlyAttention = widget.initialFilter == 'attention';
  int _page = 0;
  int _totalPages = 1;
  int _total = 0;
  bool _loading = false;
  Object? _error;
  int _generation = 0;

  @override
  void initState() {
    super.initState();
    _scroll.addListener(() {
      if (_scroll.position.pixels > _scroll.position.maxScrollExtent - 400) _loadMore();
    });
    _loadCategories();
    _reload();
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _scroll.dispose();
    _search.dispose();
    super.dispose();
  }

  Future<void> _loadCategories() async {
    try {
      final data = await context.read<ApiClient>().get('/categories');
      if (mounted) setState(() => _categories = asMapList(data));
    } catch (_) {
      // El filtro de categoría es opcional.
    }
  }

  Map<String, dynamic> _query(int page) {
    final text = _search.text.trim();
    final isCode = RegExp(r'^\d{4,}$').hasMatch(text);
    return {
      'page': page,
      'per_page': _perPage,
      'sort_by': _onlyAttention ? 'stock' : 'name',
      'sort_dir': 'asc',
      if (text.isNotEmpty) (isCode ? 'barcode' : 'name'): text,
      'category_id': _categoryId,
      if (_onlyAttention) 'stock_max': lowStockLimit - 0.001,
    };
  }

  Future<void> _reload() async {
    _generation++;
    setState(() {
      _items.clear();
      _page = 0;
      _totalPages = 1;
      _error = null;
    });
    await _loadMore();
  }

  Future<void> _loadMore() async {
    if (_loading || _page >= _totalPages) return;
    final generation = _generation;
    setState(() => _loading = true);
    try {
      final result = PageResult.fromJson(await context.read<ApiClient>().get('/products', query: _query(_page + 1)));
      if (!mounted || generation != _generation) return;
      setState(() {
        _items.addAll(result.items);
        _page++;
        _totalPages = result.totalPages;
        _total = result.total;
      });
    } catch (error) {
      if (mounted && generation == _generation) setState(() => _error = error);
    } finally {
      if (mounted && generation == _generation) setState(() => _loading = false);
    }
  }

  void _onSearch(String _) {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 400), _reload);
  }

  Future<void> _create() async {
    final created = await Navigator.of(context).push<Map<String, dynamic>>(
      MaterialPageRoute(builder: (_) => const ProductFormScreen()),
    );
    if (created == null || !mounted) return;
    _reload();
    if (created['id'] != null) context.push('/products/${created['id']}');
  }

  Future<void> _scan() async {
    final code = await scanBarcode(context);
    if (code == null || !mounted) return;
    _search.text = code;
    await _reload();
    if (_items.length == 1 && mounted) context.push('/products/${_items.first['id']}');
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return ModuleScaffold(
      title: 'Productos',
      actions: [IconButton(tooltip: 'Escanear código', onPressed: _scan, icon: const Icon(Icons.qr_code_scanner))],
      floatingActionButton: FloatingActionButton.extended(onPressed: _create, icon: const Icon(Icons.add), label: const Text('Crear')),
      body: Column(children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
          child: TextField(
            controller: _search,
            onChanged: _onSearch,
            textInputAction: TextInputAction.search,
            decoration: InputDecoration(
              hintText: 'Buscar por nombre o código de barras',
              prefixIcon: const Icon(Icons.search),
              suffixIcon: _search.text.isEmpty
                  ? null
                  : IconButton(
                      tooltip: 'Limpiar',
                      icon: const Icon(Icons.close),
                      onPressed: () {
                        _search.clear();
                        _reload();
                      }),
            ),
          ),
        ),
        SizedBox(
          height: 48,
          child: ListView(scrollDirection: Axis.horizontal, padding: const EdgeInsets.symmetric(horizontal: 16), children: [
            FilterChip(
              label: const Text('Por reponer'),
              selected: _onlyAttention,
              onSelected: (value) {
                setState(() => _onlyAttention = value);
                _reload();
              },
            ),
            const SizedBox(width: 8),
            if (_categories.isNotEmpty)
              PopupMenuButton<int?>(
                initialValue: _categoryId,
                onSelected: (value) {
                  setState(() => _categoryId = value);
                  _reload();
                },
                itemBuilder: (_) => [
                  const PopupMenuItem(value: null, child: Text('Todas las categorías')),
                  for (final c in _categories)
                    PopupMenuItem(value: (c['id'] as num).toInt(), child: Text(c['name']?.toString() ?? '')),
                ],
                child: Chip(
                  avatar: const Icon(Icons.category_outlined, size: 18),
                  label: Text(_categoryId == null
                      ? 'Categoría'
                      : _categories.firstWhere((c) => c['id'] == _categoryId, orElse: () => {})['name']?.toString() ??
                          'Categoría'),
                ),
              ),
          ]),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 4),
          child: Align(
            alignment: Alignment.centerLeft,
            child: Text(_page == 0 && _loading ? 'Buscando…' : '${formatNumber(_total)} productos',
                style: theme.textTheme.bodySmall),
          ),
        ),
        Expanded(child: _buildList(theme)),
      ]),
    );
  }

  Widget _buildList(ThemeData theme) {
    if (_items.isEmpty && _loading) return const LoadingView();
    if (_items.isEmpty && _error != null) return ErrorView(error: _error!, onRetry: _reload);
    if (_items.isEmpty) {
      return const MessageView(icon: Icons.inventory_2_outlined, title: 'Sin productos', message: 'No hay productos con esos filtros.');
    }
    return RefreshIndicator(
      onRefresh: _reload,
      child: ListView.separated(
        controller: _scroll,
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.fromLTRB(16, 4, 16, 96),
        itemCount: _items.length + 1,
        separatorBuilder: (_, _) => const SizedBox(height: 8),
        itemBuilder: (context, index) {
          if (index == _items.length) {
            if (_error != null) return TextButton(onPressed: _loadMore, child: const Text('Reintentar'));
            return _page < _totalPages
                ? const Padding(padding: EdgeInsets.all(16), child: Center(child: CircularProgressIndicator()))
                : const SizedBox.shrink();
          }
          return _ProductTile(product: _items[index]);
        },
      ),
    );
  }
}

class _ProductTile extends StatelessWidget {
  const _ProductTile({required this.product});
  final Map<String, dynamic> product;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final state = stockState(product);
    final color = switch (state) {
      StockState.out => theme.colorScheme.error,
      StockState.low => Colors.orange.shade700,
      StockState.unknown => theme.colorScheme.outline,
      StockState.healthy => Colors.green.shade700,
    };
    final category = asMap(product['category'])['name']?.toString();
    return Card(
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: () async {
          final deleted = await context.push<bool>('/products/${product['id']}');
          if (deleted == true && context.mounted) context.findAncestorStateOfType<_ProductsScreenState>()?._reload();
        },
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Row(children: [
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(product['name']?.toString() ?? '', style: theme.textTheme.titleSmall),
                const SizedBox(height: 2),
                Text(
                  [?category, if (product['barcode'] != null) product['barcode'].toString()].join(' · '),
                  style: theme.textTheme.bodySmall,
                ),
                const SizedBox(height: 4),
                Text('Venta ${formatMoney(product['sale_price'])}', style: theme.textTheme.bodySmall),
              ]),
            ),
            const SizedBox(width: 12),
            Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
              Text(formatNumber(product['stock']), style: theme.textTheme.titleLarge?.copyWith(color: color)),
              Text(product['base_unit']?.toString() ?? 'existencias', style: theme.textTheme.labelSmall),
            ]),
          ]),
        ),
      ),
    );
  }
}
