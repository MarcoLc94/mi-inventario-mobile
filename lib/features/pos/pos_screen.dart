import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../core/api_client.dart';
import '../../core/files.dart';
import '../../core/formatters.dart';
import '../../core/ids.dart';
import '../../core/session.dart';
import '../../core/user_profile.dart';
import '../../widgets/app_shell.dart';
import '../../widgets/async_states.dart';
import '../../widgets/barcode_scanner.dart';
import '../../widgets/form_fields.dart';
import 'pos_models.dart';

Future<void> openTicket(BuildContext context, Map<String, dynamic> sale) async {
  try {
    await openRemotePdf(context.read<ApiClient>(), '/pos/sales/${sale['id']}/ticket', '${sale['folio'] ?? 'ticket'}.pdf');
  } catch (error) {
    if (context.mounted) showError(context, error);
  }
}

/// Punto de venta: abrir caja, buscar o escanear productos, cobrar y cerrar caja.
/// Mismas reglas que la web (src/pages/pos/PointOfSale.tsx).
class PosScreen extends StatefulWidget {
  const PosScreen({super.key});

  @override
  State<PosScreen> createState() => _PosScreenState();
}

class _PosScreenState extends State<PosScreen> {
  List<Map<String, dynamic>> _sessions = [];
  List<Map<String, dynamic>> _warehouses = [];
  Map<String, dynamic>? _defaultClient;
  bool _loading = true;
  Object? _loadError;
  bool _busy = false;

  final _opening = TextEditingController(text: '0.00');
  int? _warehouseId;

  final _search = TextEditingController();
  Timer? _debounce;
  List<Map<String, dynamic>> _catalog = [];
  bool _catalogLoading = false;
  String? _catalogError;
  int _page = 1;
  int _totalPages = 1;

  final _cart = <CartLine>[];
  Map<String, dynamic>? _lastSale;

  Map<String, dynamic>? get _current => _sessions.where((s) => s['closed_at'] == null).firstOrNull;
  ApiClient get _api => context.read<ApiClient>();

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _opening.dispose();
    _search.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _loadError = null;
    });
    try {
      final results = await Future.wait([_api.get('/pos/sessions'), _api.get('/pos/options')]);
      final options = asMap(results[1]);
      _sessions = asMapList(results[0]);
      _warehouses = asMapList(options['warehouses']);
      _defaultClient = options['default_client'] == null ? null : asMap(options['default_client']);
      _warehouseId ??= (_warehouses.firstOrNull?['id'] as num?)?.toInt();
      if (_current != null) await _loadCatalog();
    } catch (error) {
      _loadError = error;
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _reloadSessions() async {
    final data = asMapList(await _api.get('/pos/sessions'));
    if (mounted) setState(() => _sessions = data);
  }

  Future<void> _loadCatalog({int page = 1}) async {
    final session = _current;
    if (session == null) return;
    setState(() {
      _catalogLoading = true;
      _catalogError = null;
    });
    try {
      final data = asMap(await _api.get('/pos/catalog', query: {'session_id': session['id'], 'query': _search.text.trim(), 'page': page}));
      if (!mounted) return;
      setState(() {
        _catalog = page == 1 ? asMapList(data['data']) : [..._catalog, ...asMapList(data['data'])];
        _page = page;
        _totalPages = (data['total_pages'] as num?)?.toInt() ?? 1;
      });
    } catch (error) {
      if (mounted) setState(() => _catalogError = error.toString());
    } finally {
      if (mounted) setState(() => _catalogLoading = false);
    }
  }

  Future<void> _openSession() async {
    if (_warehouseId == null) return;
    setState(() => _busy = true);
    try {
      await _api.post('/pos/sessions', {'warehouse_id': _warehouseId, 'opening_amount': _opening.text.trim().isEmpty ? '0' : _opening.text.trim()});
      await _reloadSessions();
      await _loadCatalog();
    } catch (error) {
      if (mounted) showError(context, error);
      await _reloadSessions().catchError((_) {});
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  /// Agrega un producto (o una presentación suya) validando precio y existencias.
  String? _add(Map<String, dynamic> product, [String presentation = 'base']) {
    final p = asMapList(product['presentations']).where((x) => x['ref'] == presentation).firstOrNull;
    final factor = presentation == 'base' ? 1 : (toNum(p?['factor']) ?? 1);
    final available = toNum(product['available_stock']) ?? 0;
    final price = toNum(presentation == 'base' ? product['unit_price'] : (p?['sale_price'] ?? product['unit_price'])) ?? 0;
    if (available <= 0) return '${product['name']} no tiene existencias en este almacén.';
    if (price <= 0) return '${product['name']} no tiene precio de venta. Asígnale uno en Productos.';
    if (baseInCart(_cart, (product['id'] as num).toInt()) + factor > available) return 'No hay existencias suficientes de ${product['name']} para agregar otra.';
    setState(() {
      _lastSale = null;
      final key = '${product['id']}|$presentation';
      final existing = _cart.where((l) => l.key == key).firstOrNull;
      existing != null ? existing.quantity += 1 : _cart.add(CartLine(product: product, presentation: presentation));
    });
    return null;
  }

  Future<void> _scan() async {
    final code = await scanBarcode(context);
    final session = _current;
    if (code == null || session == null || !mounted) return;
    try {
      final data = asMap(await _api.get('/pos/catalog', query: {'session_id': session['id'], 'query': code, 'page': 1}));
      bool same(dynamic v) => v?.toString().toLowerCase() == code.toLowerCase();
      final matches = asMapList(data['data']).where((item) {
        final codes = (item['barcodes'] as List?) ?? [item['barcode']];
        return codes.any(same) || asMapList(item['presentations']).any((p) => same(p['barcode']));
      }).toList();
      if (!mounted) return;
      if (matches.isEmpty) return showMessage(context, 'No hay ningún producto con el código $code en este almacén.');
      if (matches.length > 1) {
        _search.text = code;
        await _loadCatalog();
        if (mounted) showMessage(context, 'El código $code está en ${matches.length} productos. Elige el correcto.');
        return;
      }
      final product = matches.first;
      final presentation = asMapList(product['presentations']).where((p) => same(p['barcode'])).firstOrNull;
      final error = _add(product, presentation?['ref']?.toString() ?? 'base');
      showMessage(context, error ?? 'Agregado: ${presentation != null ? '${presentation['name']} de ' : ''}${product['name']}');
    } catch (error) {
      if (mounted) showError(context, error);
    }
  }

  Future<void> _openCart() async {
    final session = _current;
    if (session == null) return;
    final sale = await Navigator.of(context).push<Map<String, dynamic>>(MaterialPageRoute(
      builder: (_) => PosCartScreen(session: session, cart: _cart, defaultClient: _defaultClient),
    ));
    if (!mounted) return;
    setState(() {});
    if (sale != null) {
      setState(() {
        _cart.clear();
        _lastSale = sale;
      });
      await _reloadSessions().catchError((_) {});
      await _loadCatalog();
    }
  }

  Future<void> _closeSession() async {
    final session = _current;
    if (session == null) return;
    final counted = await showDialog<String>(
      context: context,
      builder: (context) => _CloseSessionDialog(session: session),
    );
    if (counted == null || !mounted) return;
    setState(() => _busy = true);
    try {
      await _api.post('/pos/sessions/${session['id']}/close', {'counted_amount': counted});
      await _reloadSessions();
      if (mounted) {
        showMessage(context, 'Caja cerrada');
        context.go('/pos/cortes');
      }
    } catch (error) {
      if (mounted) showError(context, error);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final session = _current;
    final canUpdate = asMap(context.watch<SessionController>().profile?.raw['pos_permission'])['update'] == true;
    return ModuleScaffold(
      title: 'Cobrar',
      actions: [
        if (session != null) IconButton(tooltip: 'Escanear código', onPressed: _scan, icon: const Icon(Icons.qr_code_scanner)),
        if (session != null && canUpdate)
          PopupMenuButton<String>(
            onSelected: (_) => _cart.isEmpty ? _closeSession() : showMessage(context, 'Vacía la venta actual antes de cerrar la caja.'),
            itemBuilder: (_) => const [PopupMenuItem(value: 'close', child: Text('Cerrar caja'))],
          ),
      ],
      body: _loading
          ? const LoadingView(label: 'Cargando punto de venta…')
          : _loadError != null
              ? ErrorView(error: _loadError!, onRetry: _load)
              : session == null
                  ? _openingForm()
                  : _workspace(session),
    );
  }

  Widget _openingForm() => ListView(padding: const EdgeInsets.all(24), children: [
        const Icon(Icons.point_of_sale_outlined, size: 56),
        const SizedBox(height: 12),
        Text('Abre tu caja', style: Theme.of(context).textTheme.headlineSmall, textAlign: TextAlign.center),
        const Text('Elige el almacén de donde saldrán los productos y registra tu fondo de efectivo.', textAlign: TextAlign.center),
        const SizedBox(height: 24),
        RecordDropdown(label: 'Almacén', records: _warehouses, value: _warehouseId, icon: Icons.warehouse_outlined, onChanged: (v) => setState(() => _warehouseId = v)),
        const SizedBox(height: 12),
        TextField(
          controller: _opening,
          keyboardType: const TextInputType.numberWithOptions(decimal: true),
          decoration: const InputDecoration(labelText: 'Fondo de caja', prefixText: r'$ '),
        ),
        const SizedBox(height: 20),
        FilledButton(onPressed: _busy || _warehouseId == null ? null : _openSession, child: Text(_busy ? 'Abriendo…' : 'Abrir caja')),
      ]);

  Widget _workspace(Map<String, dynamic> session) {
    final theme = Theme.of(context);
    final items = _cart.fold<num>(0, (sum, l) => sum + l.quantity);
    return Column(children: [
      if (_lastSale != null)
        MaterialBanner(
          leading: const Icon(Icons.check_circle_outline),
          content: Text('Venta ${_lastSale!['folio']} registrada · ${money(_lastSale!['total'])}'
              '${toNum(_lastSale!['change_amount']) != null && toNum(_lastSale!['change_amount'])! > 0 ? ' · cambio ${money(_lastSale!['change_amount'])}' : ''}'),
          actions: [
            TextButton(onPressed: () => openTicket(context, _lastSale!), child: const Text('Ticket')),
            TextButton(onPressed: () => setState(() => _lastSale = null), child: const Text('Cerrar')),
          ],
        ),
      Padding(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
        child: Row(children: [
          Expanded(child: Text('Caja: ${session['warehouse_name'] ?? ''}', style: theme.textTheme.bodySmall)),
          Text('Efectivo esperado ${money(session['cash_expected'])}', style: theme.textTheme.bodySmall),
        ]),
      ),
      Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16),
        child: TextField(
          controller: _search,
          onChanged: (_) {
            _debounce?.cancel();
            _debounce = Timer(const Duration(milliseconds: 250), _loadCatalog);
          },
          decoration: InputDecoration(
            hintText: 'Buscar producto o código',
            prefixIcon: const Icon(Icons.search),
            suffixIcon: IconButton(tooltip: 'Escanear', icon: const Icon(Icons.qr_code_scanner), onPressed: _scan),
          ),
        ),
      ),
      if (_catalogLoading) const LinearProgressIndicator(minHeight: 2),
      Expanded(
        child: _catalogError != null
            ? ErrorView(error: _catalogError!, onRetry: _loadCatalog)
            : _catalog.isEmpty && !_catalogLoading
                ? const MessageView(icon: Icons.inventory_2_outlined, title: 'Sin productos', message: 'No hay productos en este almacén para la búsqueda.')
                : NotificationListener<ScrollNotification>(
                    onNotification: (n) {
                      if (n.metrics.pixels > n.metrics.maxScrollExtent - 300 && !_catalogLoading && _page < _totalPages) _loadCatalog(page: _page + 1);
                      return false;
                    },
                    child: ListView.separated(
                      padding: const EdgeInsets.fromLTRB(16, 8, 16, 100),
                      itemCount: _catalog.length,
                      separatorBuilder: (_, _) => const SizedBox(height: 6),
                      itemBuilder: (context, i) {
                        final p = _catalog[i];
                        final inCart = baseInCart(_cart, (p['id'] as num).toInt());
                        return Card(
                          child: ListTile(
                            title: Text(p['name']?.toString() ?? ''),
                            subtitle: Text('Disponible ${formatNumber(p['available_stock'])} ${p['base_unit'] ?? ''}${p['barcode'] != null ? ' · ${p['barcode']}' : ''}'),
                            trailing: Column(mainAxisAlignment: MainAxisAlignment.center, crossAxisAlignment: CrossAxisAlignment.end, children: [
                              Text(money(p['unit_price']), style: theme.textTheme.titleSmall),
                              if (inCart > 0) Text('En venta: ${formatNumber(inCart)}', style: theme.textTheme.labelSmall?.copyWith(color: theme.colorScheme.primary)),
                            ]),
                            onTap: () {
                              final error = _add(p);
                              if (error != null) showMessage(context, error);
                            },
                            onLongPress: asMapList(p['presentations']).where((x) => x['ref'] != 'base').isEmpty
                                ? null
                                : () => _choosePresentation(p),
                          ),
                        );
                      },
                    ),
                  ),
      ),
      SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 4, 16, 12),
          child: FilledButton.icon(
            onPressed: _cart.isEmpty ? null : _openCart,
            icon: const Icon(Icons.shopping_cart_outlined),
            label: Text(_cart.isEmpty ? 'Agrega productos para comenzar' : 'Ver venta (${formatNumber(items)})'),
          ),
        ),
      ),
    ]);
  }

  Future<void> _choosePresentation(Map<String, dynamic> product) async {
    final presentations = asMapList(product['presentations']).where((x) => x['ref'] != 'base').toList();
    final ref = await showModalBottomSheet<String>(
      context: context,
      builder: (sheet) => SafeArea(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          ListTile(title: Text(product['name'].toString(), style: Theme.of(sheet).textTheme.titleMedium)),
          ListTile(title: Text('Unidad (${product['base_unit'] ?? 'pz'})'), trailing: Text(money(product['unit_price'])), onTap: () => Navigator.pop(sheet, 'base')),
          for (final p in presentations)
            ListTile(
              title: Text(p['name'].toString()),
              subtitle: Text('${formatNumber(p['factor'])} ${product['base_unit'] ?? ''}'),
              trailing: Text(money(p['sale_price'])),
              onTap: () => Navigator.pop(sheet, p['ref'].toString()),
            ),
        ]),
      ),
    );
    if (ref == null || !mounted) return;
    final error = _add(product, ref);
    if (error != null) showMessage(context, error);
  }
}

class _CloseSessionDialog extends StatefulWidget {
  const _CloseSessionDialog({required this.session});
  final Map<String, dynamic> session;

  @override
  State<_CloseSessionDialog> createState() => _CloseSessionDialogState();
}

class _CloseSessionDialogState extends State<_CloseSessionDialog> {
  final _counted = TextEditingController();

  @override
  Widget build(BuildContext context) {
    final s = widget.session;
    final expected = toNum(s['cash_expected']) ?? 0;
    final counted = num.tryParse(_counted.text.trim());
    return AlertDialog(
      title: const Text('Cierre de caja'),
      content: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text('Fondo: ${money(s['opening_amount'])}'),
        Text('Ventas en efectivo: ${money(asMap(s['totals'])['cash'])}'),
        Text('Tarjeta: ${money(asMap(s['totals'])['card'])} · Transferencia: ${money(asMap(s['totals'])['transfer'])}'),
        const SizedBox(height: 8),
        Text('Efectivo esperado: ${money(expected)}', style: const TextStyle(fontWeight: FontWeight.w600)),
        const SizedBox(height: 12),
        TextField(
          controller: _counted,
          autofocus: true,
          keyboardType: const TextInputType.numberWithOptions(decimal: true),
          decoration: const InputDecoration(labelText: 'Efectivo contado', prefixText: r'$ '),
          onChanged: (_) => setState(() {}),
        ),
        if (counted != null) Padding(padding: const EdgeInsets.only(top: 8), child: Text('Diferencia: ${money(counted - expected)}')),
      ]),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancelar')),
        FilledButton(onPressed: counted == null || counted < 0 ? null : () => Navigator.pop(context, _counted.text.trim()), child: const Text('Cerrar caja')),
      ],
    );
  }
}

/// Venta actual: cantidades, cliente, total calculado por el servidor y cobro.
class PosCartScreen extends StatefulWidget {
  const PosCartScreen({super.key, required this.session, required this.cart, this.defaultClient});
  final Map<String, dynamic> session;
  final List<CartLine> cart;
  final Map<String, dynamic>? defaultClient;

  @override
  State<PosCartScreen> createState() => _PosCartScreenState();
}

class _PosCartScreenState extends State<PosCartScreen> {
  Map<String, dynamic>? _quote;
  bool _quoteLoading = false;
  String? _quoteError;
  int _quoteRequest = 0;
  late Map<String, dynamic>? _client = widget.defaultClient;
  String _method = 'cash';
  final _received = TextEditingController();
  final _reference = TextEditingController();
  bool _busy = false;
  String? _error;
  Map<String, dynamic>? _pending;

  ApiClient get _api => context.read<ApiClient>();
  String get _pendingKey => 'pos-payment-v1:${context.read<SessionController>().profile?.id}';

  @override
  void initState() {
    super.initState();
    _restorePending();
    _requote();
  }

  @override
  void dispose() {
    _received.dispose();
    _reference.dispose();
    super.dispose();
  }

  Future<void> _restorePending() async {
    final prefs = await SharedPreferences.getInstance();
    final saved = prefs.getString(_pendingKey);
    if (saved != null && mounted) setState(() => _pending = asMap(jsonDecode(saved)));
  }

  Future<void> _savePending(Map<String, dynamic>? payload) async {
    final prefs = await SharedPreferences.getInstance();
    payload == null ? await prefs.remove(_pendingKey) : await prefs.setString(_pendingKey, jsonEncode(payload));
    if (mounted) setState(() => _pending = payload);
  }

  Future<void> _requote() async {
    final request = ++_quoteRequest;
    setState(() {
      _quote = null;
      _quoteError = null;
      _quoteLoading = widget.cart.isNotEmpty;
    });
    if (widget.cart.isEmpty) return;
    try {
      final quote = asMap(await _api.post('/pos/quote', {'session_id': widget.session['id'], 'items': [for (final l in widget.cart) l.toJson()]}));
      if (mounted && request == _quoteRequest) setState(() => _quote = quote);
    } catch (error) {
      if (mounted && request == _quoteRequest) setState(() => _quoteError = error.toString());
    } finally {
      if (mounted && request == _quoteRequest) setState(() => _quoteLoading = false);
    }
  }

  void _changeQuantity(CartLine line, num delta) {
    setState(() {
      line.quantity += delta;
      if (line.quantity <= 0) widget.cart.remove(line);
    });
    _requote();
  }

  Future<void> _pickClient() async {
    final picked = await showModalBottomSheet<Map<String, dynamic>>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (_) => const _ClientPicker(),
    );
    if (picked != null) setState(() => _client = picked);
  }

  Future<void> _charge() async {
    final quote = _quote;
    if (quote == null || _client == null || _busy) return;
    final total = toNum(quote['total']) ?? 0;
    final received = _method == 'cash' ? num.tryParse(_received.text.trim()) : total;
    if (_method == 'cash' && (received == null || received < total)) {
      setState(() => _error = 'El efectivo recibido debe cubrir el total de ${money(total)}.');
      return;
    }
    final payload = {
      'session_id': widget.session['id'],
      'client_id': _client!['id'],
      'request_key': newRequestKey(),
      'expected_total': quote['total'],
      'payment_method': _method,
      'received_amount': _method == 'cash' ? _received.text.trim() : quote['total'],
      'payment_reference': _reference.text.trim(),
      'items': [for (final l in widget.cart) l.toJson()],
    };
    // Se guarda antes de enviar: si la red falla, se recupera sin cobrar dos veces.
    await _savePending(payload);
    await _submit(payload);
  }

  Future<void> _submit(Map<String, dynamic> payload) async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final sale = asMap(await _api.post('/pos/sales', payload));
      await _finish(sale);
    } on ApiException catch (error) {
      if (error.status == 409) {
        try {
          await _finish(asMap(await _api.get('/pos/sales/by_key', query: {'request_key': payload['request_key']})));
          return;
        } on ApiException catch (lookup) {
          if (lookup.status == 404) await _savePending(null);
        }
      } else if (const [400, 401, 402, 403, 404, 422].contains(error.status)) {
        await _savePending(null);
        _requote();
      }
      if (mounted) setState(() => _error = error.message);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _recover() async {
    final pending = _pending;
    if (pending == null) return;
    setState(() => _busy = true);
    try {
      await _finish(asMap(await _api.get('/pos/sales/by_key', query: {'request_key': pending['request_key']})));
    } on ApiException catch (error) {
      if (mounted) {
        setState(() => _error = error.status == 404 ? 'El cobro aún no aparece registrado. Reintenta el mismo cobro para resolverlo sin duplicarlo.' : error.message);
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _finish(Map<String, dynamic> sale) async {
    await _savePending(null);
    if (mounted) Navigator.pop(context, sale);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final quote = _quote;
    final quoteItems = asMapList(quote?['items']);
    final total = toNum(quote?['total']) ?? 0;
    final received = num.tryParse(_received.text.trim()) ?? 0;
    final locked = _busy || _pending != null;
    return Scaffold(
      appBar: AppBar(title: const Text('Venta actual'), actions: [
        TextButton(
          onPressed: locked || widget.cart.isEmpty
              ? null
              : () {
                  setState(widget.cart.clear);
                  Navigator.pop(context);
                },
          child: const Text('Vaciar'),
        ),
      ]),
      body: ListView(padding: const EdgeInsets.all(16), children: [
        if (_pending != null)
          Card(
            color: theme.colorScheme.tertiaryContainer,
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                Text('Cobro pendiente de confirmar', style: theme.textTheme.titleSmall),
                Text('${money(_pending!['expected_total'])} · ${posMethods[_pending!['payment_method']]}. Conservamos este intento para evitar cobrarlo dos veces.'),
                const SizedBox(height: 8),
                Row(children: [
                  Expanded(child: OutlinedButton(onPressed: _busy ? null : _recover, child: const Text('Comprobar'))),
                  const SizedBox(width: 8),
                  Expanded(child: FilledButton(onPressed: _busy ? null : () => _submit(_pending!), child: const Text('Reintentar'))),
                ]),
              ]),
            ),
          ),
        if (_error != null) Padding(padding: const EdgeInsets.only(bottom: 8), child: Text(_error!, style: TextStyle(color: theme.colorScheme.error))),
        for (final line in List.of(widget.cart))
          Card(
            margin: const EdgeInsets.only(bottom: 8),
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Row(children: [
                Expanded(
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text(line.name, style: theme.textTheme.titleSmall),
                    Text([
                      if (line.presentation != 'base') line.presentations.where((p) => p['ref'] == line.presentation).firstOrNull?['name'] ?? '',
                      quoteItems.where((q) => q['product_id'] == line.productId && (q['presentation'] ?? 'base') == line.presentation).map((q) => money(q['subtotal'])).firstOrNull ?? '',
                    ].where((t) => t.toString().isNotEmpty).join(' · ')),
                  ]),
                ),
                IconButton(onPressed: locked ? null : () => _changeQuantity(line, -1), icon: const Icon(Icons.remove_circle_outline)),
                Text(formatNumber(line.quantity), style: theme.textTheme.titleMedium),
                IconButton(onPressed: locked ? null : () => _changeQuantity(line, 1), icon: const Icon(Icons.add_circle_outline)),
              ]),
            ),
          ),
        const SizedBox(height: 8),
        Card(
          child: ListTile(
            leading: const Icon(Icons.person_outline),
            title: Text(_client?['name']?.toString() ?? 'Elige un cliente'),
            subtitle: const Text('Cliente'),
            trailing: TextButton(onPressed: locked ? null : _pickClient, child: const Text('Cambiar')),
          ),
        ),
        const SizedBox(height: 8),
        SectionCard(title: 'Total', children: [
          if (_quoteLoading) const Padding(padding: EdgeInsets.all(16), child: LinearProgressIndicator()),
          if (_quoteError != null) Padding(padding: const EdgeInsets.all(16), child: Text(_quoteError!, style: TextStyle(color: theme.colorScheme.error))),
          if (quote != null) ...[
            InfoRow('Subtotal', money(quote['subtotal'])),
            InfoRow('IVA (${formatNumber((toNum(quote['iva_rate']) ?? 0) * 100)} %)', money(quote['tax'])),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
              child: Row(children: [
                const Expanded(child: Text('Total')),
                Text(money(total), style: theme.textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w700)),
              ]),
            ),
          ],
          Align(
            alignment: Alignment.centerRight,
            child: TextButton(onPressed: locked ? null : _requote, child: const Text('Actualizar precios y existencias')),
          ),
        ]),
        const SizedBox(height: 8),
        Text('Forma de pago', style: theme.textTheme.titleSmall),
        const SizedBox(height: 8),
        SegmentedButton<String>(
          showSelectedIcon: false,
          segments: [
            for (final e in posMethods.entries)
              ButtonSegment(value: e.key, label: FittedBox(fit: BoxFit.scaleDown, child: Text(e.value, maxLines: 1, softWrap: false))),
          ],
          selected: {_method},
          onSelectionChanged: locked ? null : (v) => setState(() => _method = v.first),
        ),
        const SizedBox(height: 12),
        if (_method == 'cash') ...[
          TextField(
            controller: _received,
            enabled: !locked,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            decoration: const InputDecoration(labelText: 'Efectivo recibido', prefixText: r'$ '),
            onChanged: (_) => setState(() {}),
          ),
          const SizedBox(height: 4),
          Text('Cambio: ${money((received - total).clamp(0, double.infinity))}', style: theme.textTheme.titleSmall),
        ] else
          TextField(controller: _reference, enabled: !locked, decoration: const InputDecoration(labelText: 'Referencia (opcional)', hintText: 'Últimos dígitos o folio')),
        const SizedBox(height: 80),
      ]),
      bottomNavigationBar: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: FilledButton(
            onPressed: locked || quote == null || _quoteLoading || _client == null ? null : _charge,
            child: Text(_busy ? 'Registrando…' : 'Cobrar ${money(total)}'),
          ),
        ),
      ),
    );
  }
}

class _ClientPicker extends StatefulWidget {
  const _ClientPicker();

  @override
  State<_ClientPicker> createState() => _ClientPickerState();
}

class _ClientPickerState extends State<_ClientPicker> {
  final _query = TextEditingController();
  Timer? _debounce;
  List<Map<String, dynamic>> _clients = [];

  @override
  void initState() {
    super.initState();
    _search();
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _query.dispose();
    super.dispose();
  }

  Future<void> _search() async {
    try {
      final data = asMapList(await context.read<ApiClient>().get('/pos/clients', query: {'query': _query.text.trim()}));
      if (mounted) setState(() => _clients = data);
    } catch (_) {}
  }

  @override
  Widget build(BuildContext context) => Padding(
        padding: EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
        child: SizedBox(
          height: MediaQuery.of(context).size.height * .7,
          child: Column(children: [
            Padding(
              padding: const EdgeInsets.all(16),
              child: TextField(
                controller: _query,
                autofocus: true,
                onChanged: (_) {
                  _debounce?.cancel();
                  _debounce = Timer(const Duration(milliseconds: 250), _search);
                },
                decoration: const InputDecoration(hintText: 'Buscar cliente', prefixIcon: Icon(Icons.search)),
              ),
            ),
            Expanded(
              child: ListView(children: [
                for (final c in _clients)
                  ListTile(
                    title: Text(c['name']?.toString() ?? ''),
                    subtitle: c['phone'] == null ? null : Text(c['phone'].toString()),
                    onTap: () => Navigator.pop(context, c),
                  ),
              ]),
            ),
          ]),
        ),
      );
}
