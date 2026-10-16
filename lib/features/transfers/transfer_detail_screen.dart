import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../../core/api_client.dart';
import '../../core/formatters.dart';
import '../../core/user_profile.dart';
import '../../widgets/async_states.dart';
import '../../widgets/form_fields.dart';
import 'transfers_screen.dart';

class TransferDetailScreen extends StatefulWidget {
  const TransferDetailScreen({super.key, required this.id});
  final String id;

  @override
  State<TransferDetailScreen> createState() => _TransferDetailScreenState();
}

class _TransferDetailScreenState extends State<TransferDetailScreen> {
  late Future<Map<String, dynamic>> _future = _load();
  bool _changed = false;

  Future<Map<String, dynamic>> _load() async => asMap(await context.read<ApiClient>().get('/inventory_transfers/${widget.id}'));

  Future<void> _action(Map<String, dynamic> transfer, String action) async {
    if (!await runTransferAction(context, transfer, action) || !mounted) return;
    _changed = true;
    if (action == 'delete') {
      context.pop(true);
    } else {
      setState(() => _future = _load());
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) Navigator.of(context).pop(_changed);
      },
      child: Scaffold(
        appBar: AppBar(title: const Text('Transferencia')),
        body: FutureBuilder<Map<String, dynamic>>(
          future: _future,
          builder: (context, snapshot) {
            if (snapshot.connectionState != ConnectionState.done) return const LoadingView();
            if (snapshot.hasError) return ErrorView(error: snapshot.error!, onRetry: () => setState(() => _future = _load()));
            final t = snapshot.data!;
            final actions = transferActions(t['status']?.toString());
            return ListView(padding: const EdgeInsets.all(16), children: [
              Row(children: [
                Expanded(child: Text(t['transfer_number']?.toString() ?? 'Transferencia #${t['id']}', style: theme.textTheme.headlineSmall)),
                StatusChip(transferStatusLabels[t['status']] ?? '${t['status']}', color: transferStatusColor(context, t['status']?.toString())),
              ]),
              const SizedBox(height: 12),
              SectionCard(title: 'Datos', children: [
                InfoRow('Origen', asMap(t['from_warehouse'])['name']?.toString()),
                InfoRow('Destino', asMap(t['to_warehouse'])['name']?.toString()),
                InfoRow('Fecha', formatDate(t['transfer_date'])),
                InfoRow('Notas', t['notes']?.toString()),
              ]),
              const SizedBox(height: 12),
              SectionCard(title: 'Productos', children: [
                for (final item in asMapList(t['inventory_transfer_items']))
                  ListTile(
                    title: Text(asMap(item['product'])['name']?.toString() ?? 'Producto #${item['product_id']}'),
                    subtitle: item['lot_number'] == null ? null : Text('Lote ${item['lot_number']}'),
                    trailing: Text('${formatNumber(item['quantity'])} ${asMap(item['product'])['base_unit'] ?? ''}', style: theme.textTheme.titleSmall),
                  ),
              ]),
              const SizedBox(height: 16),
              for (final (action, label) in actions)
                Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: action == 'delete' || action == 'cancel'
                      ? OutlinedButton(
                          style: OutlinedButton.styleFrom(foregroundColor: theme.colorScheme.error),
                          onPressed: () => _action(t, action),
                          child: Text(label),
                        )
                      : FilledButton(onPressed: () => _action(t, action), child: Text(label)),
                ),
            ]);
          },
        ),
      ),
    );
  }
}
