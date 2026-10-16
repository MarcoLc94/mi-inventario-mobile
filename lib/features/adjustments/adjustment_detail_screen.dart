import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../../core/api_client.dart';
import '../../core/catalogs.dart';
import '../../core/files.dart';
import '../../core/formatters.dart';
import '../../core/user_profile.dart';
import '../../widgets/async_states.dart';
import '../../widgets/form_fields.dart';
import 'adjustments_screen.dart';

class AdjustmentDetailScreen extends StatefulWidget {
  const AdjustmentDetailScreen({super.key, required this.id});
  final String id;

  @override
  State<AdjustmentDetailScreen> createState() => _AdjustmentDetailScreenState();
}

class _AdjustmentDetailScreenState extends State<AdjustmentDetailScreen> {
  late Future<(Map<String, dynamic>, Map<int, String>)> _future = _load();
  bool _changed = false;

  Future<(Map<String, dynamic>, Map<int, String>)> _load() async {
    final api = context.read<ApiClient>();
    final catalogs = context.read<Catalogs>();
    final adjustment = asMap(await api.get('/inventory_adjustments/${widget.id}'));
    final warehouses = await catalogs.warehouses().catchError((_) => <Map<String, dynamic>>[]);
    return (adjustment, {for (final w in warehouses) (w['id'] as num).toInt(): w['name'].toString()});
  }

  Future<void> _action(Map<String, dynamic> adjustment, String action) async {
    if (!await runAdjustmentAction(context, adjustment, action) || !mounted) return;
    _changed = true;
    if (action == 'delete') {
      context.pop(true);
    } else {
      setState(() => _future = _load());
    }
  }

  Future<void> _pdf(Map<String, dynamic> adjustment) async {
    try {
      await openRemotePdf(context.read<ApiClient>(), '/inventory_adjustments/${adjustment['id']}/download_inventory_adjustment',
          '${adjustment['adjustment_number'] ?? 'ajuste-${adjustment['id']}'}.pdf');
    } catch (error) {
      if (mounted) showError(context, error);
    }
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) Navigator.of(context).pop(_changed);
      },
      child: Scaffold(
        appBar: AppBar(title: const Text('Ajuste de inventario')),
        body: FutureBuilder<(Map<String, dynamic>, Map<int, String>)>(
          future: _future,
          builder: (context, snapshot) {
            if (snapshot.connectionState != ConnectionState.done) return const LoadingView();
            if (snapshot.hasError) return ErrorView(error: snapshot.error!, onRetry: () => setState(() => _future = _load()));
            final (a, warehouses) = snapshot.data!;
            final pending = a['status'] == 'pending';
            final theme = Theme.of(context);
            return ListView(padding: const EdgeInsets.all(16), children: [
              Row(children: [
                Expanded(child: Text(a['adjustment_number']?.toString() ?? 'Ajuste #${a['id']}', style: theme.textTheme.headlineSmall)),
                StatusChip(adjustmentStatusLabels[a['status']] ?? '${a['status']}', color: adjustmentStatusColor(context, a['status']?.toString())),
              ]),
              const SizedBox(height: 12),
              SectionCard(title: 'Datos del ajuste', children: [
                InfoRow('Fecha', formatDate(a['adjustment_date'])),
                InfoRow('Registró', userName(a['created_by_user'])),
                InfoRow('Aprobó', a['approved_by_user'] == null ? null : userName(a['approved_by_user'])),
                InfoRow('Notas', a['notes']?.toString()),
              ]),
              const SizedBox(height: 12),
              SectionCard(title: 'Productos', children: [
                for (final item in asMapList(a['adjustment_items']))
                  Builder(builder: (context) {
                    final quantity = toNum(item['quantity']) ?? 0;
                    final color = quantity >= 0 ? Colors.green.shade700 : theme.colorScheme.error;
                    return ListTile(
                      title: Text(asMap(item['product'])['name']?.toString() ?? 'Producto #${item['product_id']}'),
                      subtitle: Text([
                        warehouses[(item['warehouse_id'] as num?)?.toInt()] ?? 'Almacén',
                        if ((item['reason']?.toString() ?? '').isNotEmpty) item['reason'],
                        if (item['lot_number'] != null) 'Lote ${item['lot_number']}',
                      ].join(' · ')),
                      trailing: Text('${quantity >= 0 ? '+' : ''}${formatNumber(quantity)} ${asMap(item['product'])['base_unit'] ?? ''}',
                          style: theme.textTheme.titleSmall?.copyWith(color: color)),
                    );
                  }),
              ]),
              const SizedBox(height: 16),
              OutlinedButton.icon(onPressed: () => _pdf(a), icon: const Icon(Icons.picture_as_pdf_outlined), label: const Text('Descargar PDF')),
              if (pending) ...[
                const SizedBox(height: 8),
                FilledButton.icon(onPressed: () => _action(a, 'approve'), icon: const Icon(Icons.check), label: const Text('Aprobar')),
                const SizedBox(height: 8),
                Row(children: [
                  Expanded(child: OutlinedButton(onPressed: () => _action(a, 'reject'), child: const Text('Rechazar'))),
                  const SizedBox(width: 8),
                  Expanded(
                    child: OutlinedButton(
                      style: OutlinedButton.styleFrom(foregroundColor: theme.colorScheme.error),
                      onPressed: () => _action(a, 'delete'),
                      child: const Text('Eliminar'),
                    ),
                  ),
                ]),
              ],
              const SizedBox(height: 24),
            ]);
          },
        ),
      ),
    );
  }
}
