import 'package:flutter/material.dart';

import '../core/api_client.dart';
import 'async_states.dart';

/// Lista paginada con desplazamiento infinito y "deslizar para actualizar".
/// Cambiar [queryKey] (p. ej. al cambiar un filtro) recarga desde la página 1.
class PagedList extends StatefulWidget {
  const PagedList({
    super.key,
    required this.fetch,
    required this.itemBuilder,
    this.queryKey,
    this.header,
    this.emptyIcon = Icons.inbox_outlined,
    this.emptyTitle = 'Sin registros',
    this.emptyMessage,
  });

  final Future<PageResult> Function(int page) fetch;
  final Widget Function(BuildContext context, Map<String, dynamic> item, VoidCallback reload) itemBuilder;
  final Object? queryKey;
  final Widget? header;
  final IconData emptyIcon;
  final String emptyTitle;
  final String? emptyMessage;

  @override
  State<PagedList> createState() => PagedListState();
}

class PagedListState extends State<PagedList> {
  final _scroll = ScrollController();
  final _items = <Map<String, dynamic>>[];
  int _page = 0;
  int _totalPages = 1;
  int total = 0;
  bool _loading = false;
  Object? _error;
  int _generation = 0;

  @override
  void initState() {
    super.initState();
    _scroll.addListener(() {
      if (_scroll.position.pixels > _scroll.position.maxScrollExtent - 400) _loadMore();
    });
    reload();
  }

  @override
  void didUpdateWidget(PagedList oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.queryKey != widget.queryKey) reload();
  }

  @override
  void dispose() {
    _scroll.dispose();
    super.dispose();
  }

  Future<void> reload() async {
    _generation++;
    setState(() {
      _items.clear();
      _page = 0;
      _totalPages = 1;
      _error = null;
      _loading = false;
    });
    await _loadMore();
  }

  Future<void> _loadMore() async {
    if (_loading || _page >= _totalPages) return;
    final generation = _generation;
    setState(() => _loading = true);
    try {
      final result = await widget.fetch(_page + 1);
      if (!mounted || generation != _generation) return;
      setState(() {
        _items.addAll(result.items);
        _page++;
        _totalPages = result.totalPages;
        total = result.total;
      });
    } catch (error) {
      if (mounted && generation == _generation) setState(() => _error = error);
    } finally {
      if (mounted && generation == _generation) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return RefreshIndicator(
      onRefresh: reload,
      child: ListView.builder(
        controller: _scroll,
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 96),
        itemCount: _items.length + 2,
        itemBuilder: (context, index) {
          if (index == 0) {
            return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              ?widget.header,
              if (_items.isEmpty && _error != null) ErrorView(error: _error!, onRetry: reload),
              if (_items.isEmpty && !_loading && _error == null)
                MessageView(icon: widget.emptyIcon, title: widget.emptyTitle, message: widget.emptyMessage),
              if (_items.isEmpty && _loading) const Padding(padding: EdgeInsets.all(48), child: Center(child: CircularProgressIndicator())),
            ]);
          }
          if (index == _items.length + 1) {
            if (_items.isEmpty) return const SizedBox.shrink();
            if (_error != null) return TextButton(onPressed: _loadMore, child: const Text('Reintentar'));
            return _page < _totalPages
                ? const Padding(padding: EdgeInsets.all(16), child: Center(child: CircularProgressIndicator()))
                : const SizedBox.shrink();
          }
          return widget.itemBuilder(context, _items[index - 1], reload);
        },
      ),
    );
  }
}

/// Convierte una respuesta en arreglo simple a una sola página.
PageResult singlePage(List<Map<String, dynamic>> items) => PageResult(items, items.length, 1);
