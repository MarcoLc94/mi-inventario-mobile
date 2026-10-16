import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../../core/api_client.dart';
import '../../core/catalogs.dart';
import '../../core/formatters.dart';
import '../../core/user_profile.dart';
import '../../widgets/async_states.dart';
import '../../widgets/form_fields.dart';
import 'warehouses_screen.dart';

/// Almacén: datos, existencias por producto y ubicaciones internas.
class WarehouseDetailScreen extends StatefulWidget {
  const WarehouseDetailScreen({super.key, required this.id});
  final String id;

  @override
  State<WarehouseDetailScreen> createState() => _WarehouseDetailScreenState();
}

class _WarehouseDetailScreenState extends State<WarehouseDetailScreen> {
  Map<String, dynamic>? _warehouse;
  List<Map<String, dynamic>> _inventory = [];
  List<Map<String, dynamic>> _locations = [];
  Object? _error;
  bool _changed = false;
  String _search = '';

  ApiClient get _api => context.read<ApiClient>();

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final results = await Future.wait([
        _api.get('/warehouses/${widget.id}'),
        _api.get('/warehouses/${widget.id}/inventory'),
        _api.get('/warehouses/${widget.id}/locations'),
      ]);
      if (!mounted) return;
      setState(() {
        _warehouse = asMap(results[0]);
        _inventory = asMapList(results[1]);
        _locations = asMapList(results[2]);
        _error = null;
      });
    } catch (error) {
      if (mounted) setState(() => _error = error);
    }
  }

  Future<void> _edit() async {
    if (await showWarehouseForm(context, _warehouse) == true) {
      _changed = true;
      await _load();
    }
  }

  Future<void> _delete() async {
    final w = _warehouse!;
    if (!await confirm(context,
            title: 'Eliminar almacén',
            message: 'Se eliminará "${w['name']}" junto con sus productos, existencias y movimientos. Esta acción no se puede deshacer.',
            action: 'Eliminar',
            destructive: true) ||
        !mounted) {
      return;
    }
    try {
      await _api.delete('/warehouses/${widget.id}');
      if (!mounted) return;
      context.read<Catalogs>().invalidate(warehouses: true);
      context.pop(true);
    } catch (error) {
      if (mounted) showError(context, error);
    }
  }

  Future<void> _locationForm([Map<String, dynamic>? location]) async {
    final saved = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (_) => _LocationForm(warehouseId: widget.id, location: location),
    );
    if (saved == true) await _load();
  }

  Future<void> _deleteLocation(Map<String, dynamic> location) async {
    if (!await confirm(context, title: 'Eliminar ubicación', message: '¿Eliminar "${location['name']}"? El inventario se queda en el almacén sin ubicación.', action: 'Eliminar', destructive: true) ||
        !mounted) {
      return;
    }
    try {
      await _api.delete('/warehouses/${widget.id}/locations/${location['id']}');
      await _load();
    } catch (error) {
      if (mounted) showError(context, error);
    }
  }

  @override
  Widget build(BuildContext context) {
    final w = _warehouse;
    final theme = Theme.of(context);
    final items = _inventory.where((i) => '${asMap(i['product'])['name']} ${asMap(i['product'])['barcode'] ?? ''}'.toLowerCase().contains(_search.toLowerCase())).toList();
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) Navigator.of(context).pop(_changed);
      },
      child: Scaffold(
        appBar: AppBar(
          title: Text(w?['name']?.toString() ?? 'Almacén'),
          actions: [
            if (w != null) IconButton(tooltip: 'Editar', onPressed: _edit, icon: const Icon(Icons.edit_outlined)),
            if (w != null) PopupMenuButton<String>(onSelected: (_) => _delete(), itemBuilder: (_) => const [PopupMenuItem(value: 'delete', child: Text('Eliminar almacén'))]),
          ],
        ),
        body: w == null
            ? (_error != null ? ErrorView(error: _error!, onRetry: _load) : const LoadingView())
            : RefreshIndicator(
                onRefresh: _load,
                child: ListView(padding: const EdgeInsets.all(16), children: [
                  SectionCard(title: 'Datos', children: [
                    InfoRow('Ubicación', w['location']?.toString()),
                    InfoRow('Descripción', w['description']?.toString()),
                    InfoRow('Estado', w['is_active'] == false ? 'Inactivo' : 'Activo'),
                    InfoRow('Productos', formatNumber(w['products_count'] ?? _inventory.length)),
                  ]),
                  const SizedBox(height: 12),
                  SectionCard(
                    title: 'Ubicaciones',
                    trailing: TextButton.icon(onPressed: () => _locationForm(), icon: const Icon(Icons.add, size: 18), label: const Text('Agregar')),
                    children: [
                      if (_locations.isEmpty) const Padding(padding: EdgeInsets.fromLTRB(16, 0, 16, 8), child: Text('Organiza el almacén por pasillos o anaqueles.')),
                      for (final l in _locations)
                        ListTile(
                          dense: true,
                          leading: const Icon(Icons.place_outlined),
                          title: Text(l['name']?.toString() ?? ''),
                          subtitle: Text([if (l['location_code'] != null) l['location_code'], '${formatNumber(l['spaces_available'] ?? 0)} espacios'].join(' · ')),
                          trailing: PopupMenuButton<String>(
                            onSelected: (v) => v == 'edit' ? _locationForm(l) : _deleteLocation(l),
                            itemBuilder: (_) => const [PopupMenuItem(value: 'edit', child: Text('Editar')), PopupMenuItem(value: 'delete', child: Text('Eliminar'))],
                          ),
                        ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  Text('Existencias', style: theme.textTheme.titleMedium),
                  const SizedBox(height: 8),
                  TextField(onChanged: (v) => setState(() => _search = v), decoration: const InputDecoration(hintText: 'Buscar producto', prefixIcon: Icon(Icons.search))),
                  const SizedBox(height: 8),
                  for (final i in items)
                    Card(
                      margin: const EdgeInsets.only(bottom: 6),
                      child: ListTile(
                        title: Text(asMap(i['product'])['name']?.toString() ?? ''),
                        subtitle: Text([
                          'Disponible ${formatNumber(i['available_stock'])}',
                          if ((toNum(i['reserved_stock']) ?? 0) > 0) 'Reservado ${formatNumber(i['reserved_stock'])}',
                          if ((toNum(i['min_stock']) ?? 0) > 0) 'Mínimo ${formatNumber(i['min_stock'])}',
                        ].join(' · ')),
                        trailing: Text('${formatNumber(i['stock'])} ${asMap(i['product'])['base_unit'] ?? ''}', style: theme.textTheme.titleSmall),
                        onTap: () => context.push('/products/${asMap(i['product'])['id']}'),
                      ),
                    ),
                  const SizedBox(height: 24),
                ]),
              ),
      ),
    );
  }
}

class _LocationForm extends StatefulWidget {
  const _LocationForm({required this.warehouseId, this.location});
  final String warehouseId;
  final Map<String, dynamic>? location;

  @override
  State<_LocationForm> createState() => _LocationFormState();
}

class _LocationFormState extends State<_LocationForm> {
  late final _name = TextEditingController(text: widget.location?['name']?.toString());
  late final _code = TextEditingController(text: widget.location?['location_code']?.toString());
  late final _spaces = TextEditingController(text: widget.location?['spaces_available']?.toString() ?? '0');
  late final _description = TextEditingController(text: widget.location?['description']?.toString());
  bool _busy = false;
  String? _error;

  Future<void> _save() async {
    final spaces = int.tryParse(_spaces.text.trim());
    if (_name.text.trim().isEmpty || spaces == null || spaces < 0) {
      setState(() => _error = 'Escribe el nombre y un número de espacios válido.');
      return;
    }
    setState(() => _busy = true);
    final body = {
      'location': {'name': _name.text.trim(), 'location_code': _code.text.trim(), 'spaces_available': spaces, 'description': _description.text.trim()},
    };
    try {
      final api = context.read<ApiClient>();
      final base = '/warehouses/${widget.warehouseId}/locations';
      widget.location == null ? await api.post(base, body) : await api.patch('$base/${widget.location!['id']}', body);
      if (mounted) Navigator.pop(context, true);
    } catch (error) {
      if (mounted) setState(() => _error = error.toString());
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => Padding(
        padding: EdgeInsets.fromLTRB(16, 16, 16, MediaQuery.of(context).viewInsets.bottom + 16),
        child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Text(widget.location == null ? 'Nueva ubicación' : 'Editar ubicación', style: Theme.of(context).textTheme.titleLarge),
          const SizedBox(height: 12),
          if (_error != null) Text(_error!, style: TextStyle(color: Theme.of(context).colorScheme.error)),
          TextField(controller: _name, decoration: const InputDecoration(labelText: 'Nombre *', hintText: 'Ej. Pasillo A')),
          const SizedBox(height: 12),
          Row(children: [
            Expanded(child: TextField(controller: _code, decoration: const InputDecoration(labelText: 'Código', hintText: 'A-01'))),
            const SizedBox(width: 8),
            Expanded(child: TextField(controller: _spaces, keyboardType: TextInputType.number, decoration: const InputDecoration(labelText: 'Espacios'))),
          ]),
          const SizedBox(height: 12),
          TextField(controller: _description, decoration: const InputDecoration(labelText: 'Descripción')),
          const SizedBox(height: 16),
          FilledButton(onPressed: _busy ? null : _save, child: Text(_busy ? 'Guardando…' : 'Guardar')),
        ]),
      );
}
