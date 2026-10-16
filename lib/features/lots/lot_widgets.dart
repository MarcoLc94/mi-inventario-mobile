import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../../core/api_client.dart';
import '../../core/formatters.dart';
import '../../core/user_profile.dart';
import '../../widgets/async_states.dart';
import '../../widgets/form_fields.dart';

/// Estado de un lote, con las mismas reglas que la web (services/lots/lots.ts).
({String label, Color color}) lotStatus(BuildContext context, Map<String, dynamic> lot) {
  final scheme = Theme.of(context).colorScheme;
  if (lot['blocked'] == true) return (label: 'Bloqueado', color: Colors.grey.shade700);
  switch (lot['expiration_status']) {
    case 'expired':
      return (label: 'Caducado', color: scheme.error);
    case 'expiring':
      final days = (lot['days_to_expiration'] as num?)?.toInt() ?? 0;
      return (label: 'Caduca en $days d', color: days <= 30 ? Colors.deepOrange : Colors.orange.shade800);
    case 'no_expiration':
      return (label: 'Sin caducidad', color: scheme.outline);
    default:
      return (label: 'Vigente', color: Colors.green.shade700);
  }
}

class LotStatusChip extends StatelessWidget {
  const LotStatusChip(this.lot, {super.key});
  final Map<String, dynamic> lot;

  @override
  Widget build(BuildContext context) {
    final status = lotStatus(context, lot);
    return StatusChip(status.label, color: status.color);
  }
}

/// Control de lotes en el detalle del producto: activarlo y ver sus lotes con
/// existencia en orden de salida (el que caduca primero arriba).
class ProductLotsCard extends StatefulWidget {
  const ProductLotsCard({super.key, required this.product, required this.onChanged});
  final Map<String, dynamic> product;
  final Future<void> Function() onChanged;

  @override
  State<ProductLotsCard> createState() => _ProductLotsCardState();
}

class _ProductLotsCardState extends State<ProductLotsCard> {
  Future<List<Map<String, dynamic>>>? _lots;
  bool _saving = false;

  bool get _tracks => widget.product['tracks_lots'] == true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void didUpdateWidget(ProductLotsCard old) {
    super.didUpdateWidget(old);
    if (old.product['stock'] != widget.product['stock'] || old.product['tracks_lots'] != widget.product['tracks_lots']) _load();
  }

  void _load() {
    _lots = _tracks
        ? context
            .read<ApiClient>()
            .get('/inventory_lots', query: {'product_id': widget.product['id'], 'per_page': 50})
            .then((data) => PageResult.fromJson(data).items)
        : null;
  }

  Future<void> _toggle(bool enabled) async {
    if (!enabled &&
        !await confirm(context,
            title: 'Desactivar lotes',
            message: 'Las nuevas entradas y salidas ya no pedirán lote. Los lotes registrados se conservan.',
            action: 'Desactivar')) {
      return;
    }
    if (!mounted) return;
    setState(() => _saving = true);
    try {
      await context.read<ApiClient>().patch('/products/${widget.product['id']}', {
        'product': {'tracks_lots': enabled},
      });
      await widget.onChanged();
    } catch (error) {
      if (mounted) showError(context, error);
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return SectionCard(title: 'Lotes y caducidades', children: [
      SwitchListTile(
        title: const Text('Controlar lotes'),
        subtitle: const Text('Las salidas toman primero el lote que caduca antes.'),
        value: _tracks,
        onChanged: _saving ? null : _toggle,
      ),
      if (_lots != null)
        FutureBuilder<List<Map<String, dynamic>>>(
          future: _lots,
          builder: (context, snapshot) {
            if (snapshot.connectionState != ConnectionState.done) {
              return const Padding(padding: EdgeInsets.all(16), child: LinearProgressIndicator());
            }
            final lots = snapshot.data ?? const [];
            if (lots.isEmpty) return const Padding(padding: EdgeInsets.fromLTRB(16, 0, 16, 8), child: Text('Sin lotes con existencia.'));
            return Column(children: [
              for (final lot in lots)
                ListTile(
                  dense: true,
                  title: Text(lot['lot_number']?.toString() ?? ''),
                  subtitle: Text('${asMap(lot['warehouse'])['name'] ?? ''} · caduca ${formatDate(lot['expiration_date'])}'),
                  trailing: Column(mainAxisAlignment: MainAxisAlignment.center, crossAxisAlignment: CrossAxisAlignment.end, children: [
                    Text(formatNumber(lot['stock'])),
                    LotStatusChip(lot),
                  ]),
                  onTap: () => context.push('/inventory/lots/${lot['id']}'),
                ),
            ]);
          },
        ),
    ]);
  }
}
