import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/api_client.dart';
import '../../core/formatters.dart';
import '../../core/user_profile.dart';
import '../../widgets/async_states.dart';
import '../../widgets/form_fields.dart';
import 'lot_widgets.dart';

const _referenceLabels = {
  'SaleOrder': 'Venta',
  'PurchaseOrderItem': 'Compra',
  'ManualInventoryMovement': 'Movimiento manual',
  'InventoryTransferItem': 'Transferencia',
  'AdjustmentItem': 'Ajuste',
  'InventoryAdjustment': 'Ajuste (reversión)',
  'InternalConsumptionItem': 'Consumo interno',
  'SupplierReturnItem': 'Devolución a proveedor',
  'ReturnItem': 'Devolución de cliente',
  'InventoryMovementInItem': 'Entrada',
  'InventoryMovementOutItem': 'Salida',
  'Product': 'Alta de producto',
  'Invoice': 'Factura de compra',
  'InventoryLot': 'Asignación de lote',
};

class LotDetailScreen extends StatefulWidget {
  const LotDetailScreen({super.key, required this.id});
  final String id;

  @override
  State<LotDetailScreen> createState() => _LotDetailScreenState();
}

class _LotDetailScreenState extends State<LotDetailScreen> {
  Map<String, dynamic>? _lot;
  Object? _error;
  bool _saving = false;
  String? _expiration;
  String? _manufactured;
  final _notes = TextEditingController();

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _notes.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    try {
      final lot = asMap(await context.read<ApiClient>().get('/inventory_lots/${widget.id}'));
      if (!mounted) return;
      setState(() {
        _lot = lot;
        _error = null;
        _expiration = lot['expiration_date']?.toString();
        _manufactured = lot['manufactured_on']?.toString();
        _notes.text = lot['notes']?.toString() ?? '';
      });
    } catch (error) {
      if (mounted) setState(() => _error = error);
    }
  }

  Future<void> _update(Map<String, dynamic> data, String message) async {
    setState(() => _saving = true);
    try {
      await context.read<ApiClient>().patch('/inventory_lots/${widget.id}', {'inventory_lot': data});
      if (!mounted) return;
      showMessage(context, message);
      await _load();
    } catch (error) {
      if (mounted) showError(context, error);
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _block() async {
    final reason = await promptText(context, title: 'Bloquear lote', label: 'Motivo del bloqueo (ej. retiro sanitario)', action: 'Bloquear lote');
    if (reason != null) await _update({'blocked': true, 'block_reason': reason}, 'Lote bloqueado');
  }

  @override
  Widget build(BuildContext context) {
    final lot = _lot;
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(title: Text(lot == null ? 'Lote' : 'Lote ${lot['lot_number']}')),
      body: lot == null
          ? (_error != null ? ErrorView(error: _error!, onRetry: _load) : const LoadingView())
          : RefreshIndicator(
              onRefresh: _load,
              child: ListView(padding: const EdgeInsets.all(16), children: [
                Text(asMap(lot['product'])['name']?.toString() ?? '', style: theme.textTheme.headlineSmall),
                Text(asMap(lot['warehouse'])['name']?.toString() ?? '', style: theme.textTheme.bodyMedium),
                const SizedBox(height: 8),
                Align(alignment: Alignment.centerLeft, child: LotStatusChip(lot)),
                const SizedBox(height: 12),
                SectionCard(title: 'Resumen', children: [
                  InfoRow('Existencia', '${formatNumber(lot['stock'])} ${asMap(lot['product'])['base_unit'] ?? ''}'),
                  InfoRow('Caducidad', formatDate(lot['expiration_date'])),
                  InfoRow('Fabricación', lot['manufactured_on'] == null ? null : formatDate(lot['manufactured_on'])),
                  InfoRow('Costo unitario', lot['unit_cost'] == null ? null : formatMoney(lot['unit_cost'])),
                ]),
                const SizedBox(height: 12),
                SectionCard(title: 'Venta del lote', children: [
                  if (lot['blocked'] == true) ...[
                    InfoRow('Bloqueado', lot['block_reason']?.toString() ?? 'Sin motivo'),
                    Padding(
                      padding: const EdgeInsets.all(16),
                      child: OutlinedButton(
                        onPressed: _saving ? null : () => _update({'blocked': false}, 'Lote desbloqueado'),
                        child: const Text('Desbloquear'),
                      ),
                    ),
                  ] else ...[
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 16),
                      child: Text(lot['expiration_status'] == 'expired'
                          ? 'Caducado: las ventas ya no lo toman.'
                          : 'Disponible para venta. Las ventas toman primero el lote que caduca antes.'),
                    ),
                    Padding(
                      padding: const EdgeInsets.all(16),
                      child: OutlinedButton.icon(
                        onPressed: _saving ? null : _block,
                        icon: const Icon(Icons.block),
                        label: const Text('Bloquear para venta (cuarentena o retiro)'),
                      ),
                    ),
                  ],
                ]),
                const SizedBox(height: 12),
                SectionCard(title: 'Datos del lote', children: [
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
                    child: DateField(label: 'Caducidad', value: _expiration, clearable: true, onChanged: (v) => setState(() => _expiration = v)),
                  ),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
                    child: DateField(label: 'Fabricación', value: _manufactured, clearable: true, onChanged: (v) => setState(() => _manufactured = v)),
                  ),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
                    child: TextField(controller: _notes, maxLines: 2, decoration: const InputDecoration(labelText: 'Notas')),
                  ),
                  Padding(
                    padding: const EdgeInsets.all(16),
                    child: FilledButton(
                      onPressed: _saving
                          ? null
                          : () => _update({'expiration_date': _expiration, 'manufactured_on': _manufactured, 'notes': _notes.text.trim()}, 'Lote actualizado'),
                      child: const Text('Guardar cambios'),
                    ),
                  ),
                ]),
                const SizedBox(height: 12),
                SectionCard(title: '¿A quién se vendió?', children: [
                  if (asMapList(lot['sales']).isEmpty) const Padding(padding: EdgeInsets.fromLTRB(16, 0, 16, 8), child: Text('Este lote no tiene ventas.')),
                  for (final sale in asMapList(lot['sales']))
                    ListTile(
                      dense: true,
                      title: Text(asMap(sale['client'])['name']?.toString() ?? 'Público en general'),
                      subtitle: Text('${sale['order_number'] ?? 'Venta #${sale['sale_order_id']}'} · ${formatDate(sale['order_date'])}'),
                      trailing: Text(formatNumber(sale['quantity'])),
                    ),
                ]),
                const SizedBox(height: 12),
                SectionCard(title: 'Movimientos del lote', children: [
                  if (asMapList(lot['movements']).isEmpty) const Padding(padding: EdgeInsets.fromLTRB(16, 0, 16, 8), child: Text('Sin movimientos.')),
                  for (final m in asMapList(lot['movements']))
                    ListTile(
                      dense: true,
                      leading: Icon(m['movement_type'] == 'IN' ? Icons.south_west : Icons.north_east,
                          color: m['movement_type'] == 'IN' ? Colors.green.shade700 : theme.colorScheme.error),
                      title: Text(_referenceLabels[m['reference_type']] ?? (m['movement_type'] == 'IN' ? 'Entrada' : 'Salida')),
                      subtitle: Text(formatDateTime(m['created_at'])),
                      trailing: Text('${m['movement_type'] == 'IN' ? '+' : '-'}${formatNumber(m['quantity'])}'),
                    ),
                ]),
                const SizedBox(height: 24),
              ]),
            ),
    );
  }
}
