import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../../core/api_client.dart';
import '../../core/formatters.dart';
import '../../core/user_profile.dart';
import '../../widgets/app_shell.dart';
import '../../widgets/async_states.dart';
import '../../widgets/form_fields.dart';

const transferStatusLabels = {
  'draft': 'Borrador',
  'pending': 'Pendiente',
  'in_transit': 'En tránsito',
  'completed': 'Completada',
  'cancelled': 'Cancelada',
};

Color transferStatusColor(BuildContext context, String? status) => switch (status) {
      'draft' => Colors.orange.shade800,
      'pending' => Colors.blue.shade700,
      'in_transit' => Theme.of(context).colorScheme.primary,
      'completed' => Colors.green.shade700,
      'cancelled' => Theme.of(context).colorScheme.error,
      _ => Theme.of(context).colorScheme.outline,
    };

/// Acciones disponibles según el estado, igual que la web.
List<(String action, String label)> transferActions(String? status) => switch (status) {
      'draft' => [('submit', 'Enviar a aprobación'), ('delete', 'Eliminar')],
      'pending' => [('approve', 'Aprobar y enviar'), ('cancel', 'Cancelar')],
      'in_transit' => [('complete', 'Marcar como recibida'), ('cancel', 'Cancelar')],
      _ => const [],
    };

Future<bool> runTransferAction(BuildContext context, Map<String, dynamic> transfer, String action) async {
  final number = transfer['transfer_number'] ?? '#${transfer['id']}';
  final destructive = action == 'delete' || action == 'cancel';
  final message = switch (action) {
    'submit' => 'La transferencia $number quedará pendiente de aprobación.',
    'approve' => 'Se descontarán las existencias del almacén de origen.',
    'complete' => 'Se sumarán las existencias en el almacén de destino.',
    'cancel' => '¿Cancelar la transferencia $number?',
    _ => '¿Eliminar la transferencia $number?',
  };
  final label = transferActions(transfer['status']?.toString()).firstWhere((a) => a.$1 == action, orElse: () => (action, 'Aceptar')).$2;
  if (!await confirm(context, title: label, message: message, action: label, destructive: destructive) || !context.mounted) return false;
  try {
    final api = context.read<ApiClient>();
    action == 'delete' ? await api.delete('/inventory_transfers/${transfer['id']}') : await api.post('/inventory_transfers/${transfer['id']}/$action', {});
    return true;
  } catch (error) {
    if (context.mounted) showError(context, error);
    return false;
  }
}

class TransfersScreen extends StatefulWidget {
  const TransfersScreen({super.key});

  @override
  State<TransfersScreen> createState() => _TransfersScreenState();
}

class _TransfersScreenState extends State<TransfersScreen> {
  late Future<List<Map<String, dynamic>>> _future = _load();
  String? _status;

  Future<List<Map<String, dynamic>>> _load() async => asMapList(await context.read<ApiClient>().get('/inventory_transfers'));
  void _reload() => setState(() => _future = _load());

  @override
  Widget build(BuildContext context) {
    return ModuleScaffold(
      title: 'Transferencias',
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () async {
          final created = await context.push<bool>('/transfers/new');
          if (created == true) _reload();
        },
        icon: const Icon(Icons.add),
        label: const Text('Nueva'),
      ),
      body: FutureBuilder<List<Map<String, dynamic>>>(
        future: _future,
        builder: (context, snapshot) {
          if (snapshot.connectionState != ConnectionState.done) return const LoadingView();
          if (snapshot.hasError) return ErrorView(error: snapshot.error!, onRetry: _reload);
          final items = snapshot.data!.where((t) => _status == null || t['status'] == _status).toList();
          return RefreshIndicator(
            onRefresh: () async => _reload(),
            child: ListView(padding: const EdgeInsets.fromLTRB(16, 8, 16, 96), children: [
              SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: Row(children: [
                  for (final entry in {null: 'Todas', ...transferStatusLabels}.entries)
                    Padding(
                      padding: const EdgeInsets.only(right: 8),
                      child: ChoiceChip(label: Text(entry.value), selected: _status == entry.key, onSelected: (_) => setState(() => _status = entry.key)),
                    ),
                ]),
              ),
              const SizedBox(height: 8),
              if (items.isEmpty) const MessageView(icon: Icons.swap_horiz, title: 'Sin transferencias', message: 'Mueve existencias entre tus almacenes.'),
              for (final t in items)
                Card(
                  margin: const EdgeInsets.only(bottom: 8),
                  child: ListTile(
                    title: Text(t['transfer_number']?.toString() ?? 'Transferencia #${t['id']}'),
                    subtitle: Text('${asMap(t['from_warehouse'])['name'] ?? '—'} → ${asMap(t['to_warehouse'])['name'] ?? '—'}\n'
                        '${formatDate(t['transfer_date'])} · ${asMapList(t['inventory_transfer_items']).length} productos'),
                    isThreeLine: true,
                    trailing: StatusChip(transferStatusLabels[t['status']] ?? '${t['status']}', color: transferStatusColor(context, t['status']?.toString())),
                    onTap: () async {
                      final changed = await context.push<bool>('/transfers/${t['id']}');
                      if (changed == true) _reload();
                    },
                  ),
                ),
            ]),
          );
        },
      ),
    );
  }
}
