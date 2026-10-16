import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../../core/api_client.dart';
import '../../core/catalogs.dart';
import '../../core/formatters.dart';
import '../../core/user_profile.dart';
import '../../widgets/app_shell.dart';
import '../../widgets/async_states.dart';
import 'lot_widgets.dart';
import 'register_lot_sheet.dart';

class _Bucket {
  const _Bucket(this.summaryKey, this.label, this.icon, this.query);
  final String summaryKey;
  final String label;
  final IconData icon;
  final Map<String, dynamic> query;
}

const _buckets = [
  _Bucket('expired', 'Caducados', Icons.event_busy, {'status': 'expired'}),
  _Bucket('within_30_days', 'Caducan en 30 días', Icons.warning_amber_rounded, {'status': 'expiring', 'days': 30}),
  _Bucket('within_60_days', 'En 31 a 60 días', Icons.schedule, {'status': 'expiring', 'days': 60}),
  _Bucket('within_90_days', 'En 61 a 90 días', Icons.schedule, {'status': 'expiring', 'days': 90}),
  _Bucket('blocked', 'Bloqueados', Icons.block, {'status': 'blocked'}),
];

class LotsScreen extends StatefulWidget {
  const LotsScreen({super.key});

  @override
  State<LotsScreen> createState() => _LotsScreenState();
}

class _LotsScreenState extends State<LotsScreen> {
  _Bucket? _bucket;
  int? _warehouseId;
  String _search = '';
  List<Map<String, dynamic>> _warehouses = [];
  Map<String, dynamic> _summary = {};
  late Future<List<Map<String, dynamic>>> _future = _load();

  @override
  void initState() {
    super.initState();
    context.read<Catalogs>().warehouses().then((w) {
      if (mounted) setState(() => _warehouses = w);
    }).catchError((_) {});
  }

  Future<List<Map<String, dynamic>>> _load() async {
    final api = context.read<ApiClient>();
    final results = await Future.wait([
      api.get('/inventory_lots', query: {'with_stock': true, 'per_page': 1000, 'warehouse_id': _warehouseId, ...?_bucket?.query}),
      api.get('/inventory_lots/expiring_summary', query: {'warehouse_id': _warehouseId}).catchError((_) => <String, dynamic>{}),
    ]);
    if (mounted) setState(() => _summary = asMap(results[1]));
    return PageResult.fromJson(results[0]).items;
  }

  void _reload() => setState(() => _future = _load());

  Future<void> _register() async {
    final created = await showRegisterLotSheet(context);
    if (created != null) _reload();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return ModuleScaffold(
      title: 'Lotes y caducidades',
      floatingActionButton: FloatingActionButton.extended(onPressed: _register, icon: const Icon(Icons.add), label: const Text('Registrar lote')),
      body: RefreshIndicator(
        onRefresh: () async => _reload(),
        child: FutureBuilder<List<Map<String, dynamic>>>(
          future: _future,
          builder: (context, snapshot) {
            final lots = (snapshot.data ?? const <Map<String, dynamic>>[]).where((lot) {
              final text = '${lot['lot_number']} ${asMap(lot['product'])['name']} ${asMap(lot['product'])['barcode'] ?? ''}'.toLowerCase();
              return text.contains(_search.toLowerCase());
            }).toList();
            return ListView(padding: const EdgeInsets.fromLTRB(16, 12, 16, 96), children: [
              Text('Alertas de caducidad', style: theme.textTheme.titleSmall),
              const SizedBox(height: 8),
              SizedBox(
                height: 96,
                child: ListView.separated(
                  scrollDirection: Axis.horizontal,
                  itemCount: _buckets.length,
                  separatorBuilder: (_, _) => const SizedBox(width: 8),
                  itemBuilder: (_, i) {
                    final bucket = _buckets[i];
                    final data = asMap(_summary[bucket.summaryKey]);
                    final selected = _bucket == bucket;
                    return SizedBox(
                      width: 150,
                      child: Card(
                        color: selected ? theme.colorScheme.secondaryContainer : null,
                        clipBehavior: Clip.antiAlias,
                        child: InkWell(
                          onTap: () {
                            setState(() => _bucket = selected ? null : bucket);
                            _reload();
                          },
                          child: Padding(
                            padding: const EdgeInsets.all(12),
                            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                              Row(children: [
                                Expanded(child: Text(bucket.label, style: theme.textTheme.labelSmall, maxLines: 2)),
                                Icon(bucket.icon, size: 18),
                              ]),
                              const Spacer(),
                              Text('${formatNumber(data['lots'] ?? 0)} lotes', style: theme.textTheme.titleMedium),
                              Text(formatMoney(data['value'] ?? 0), style: theme.textTheme.labelSmall),
                            ]),
                          ),
                        ),
                      ),
                    );
                  },
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                onChanged: (v) => setState(() => _search = v),
                decoration: const InputDecoration(hintText: 'Buscar lote o producto', prefixIcon: Icon(Icons.search)),
              ),
              if (_warehouses.length > 1) ...[
                const SizedBox(height: 8),
                DropdownButtonFormField<int?>(
                  initialValue: _warehouseId,
                  decoration: const InputDecoration(labelText: 'Almacén', prefixIcon: Icon(Icons.warehouse_outlined)),
                  items: [
                    const DropdownMenuItem<int?>(value: null, child: Text('Todos los almacenes')),
                    for (final w in _warehouses) DropdownMenuItem<int?>(value: (w['id'] as num).toInt(), child: Text(w['name'].toString())),
                  ],
                  onChanged: (v) {
                    setState(() => _warehouseId = v);
                    _reload();
                  },
                ),
              ],
              const SizedBox(height: 12),
              if (snapshot.connectionState != ConnectionState.done)
                const Padding(padding: EdgeInsets.all(32), child: Center(child: CircularProgressIndicator()))
              else if (snapshot.hasError)
                ErrorView(error: snapshot.error!, onRetry: _reload)
              else if (lots.isEmpty)
                MessageView(
                  icon: Icons.event_busy_outlined,
                  title: _bucket == null ? 'Aún no tienes lotes' : 'No hay lotes con este filtro',
                  message: 'Registra un lote nuevo o activa "Asignar lote" al dar de alta un producto.',
                )
              else
                for (final lot in lots)
                  Card(
                    margin: const EdgeInsets.only(bottom: 8),
                    child: ListTile(
                      title: Text('${asMap(lot['product'])['name'] ?? ''}'),
                      subtitle: Text('Lote ${lot['lot_number']} · ${asMap(lot['warehouse'])['name'] ?? ''}\nCaduca ${formatDate(lot['expiration_date'])}'),
                      isThreeLine: true,
                      trailing: Column(mainAxisAlignment: MainAxisAlignment.center, crossAxisAlignment: CrossAxisAlignment.end, children: [
                        Text(formatNumber(lot['stock']), style: theme.textTheme.titleMedium),
                        LotStatusChip(lot),
                      ]),
                      onTap: () async {
                        await context.push('/inventory/lots/${lot['id']}');
                        _reload();
                      },
                    ),
                  ),
            ]);
          },
        ),
      ),
    );
  }
}
