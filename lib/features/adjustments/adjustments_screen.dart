import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../../core/api_client.dart';
import '../../core/formatters.dart';
import '../../core/user_profile.dart';
import '../../widgets/app_shell.dart';
import '../../widgets/async_states.dart';
import '../../widgets/form_fields.dart';

const adjustmentStatusLabels = {
  'pending': 'Pendiente',
  'approved': 'Aprobado',
  'completed': 'Completado',
  'rejected': 'Rechazado',
};

Color adjustmentStatusColor(BuildContext context, String? status) => switch (status) {
      'pending' => Colors.orange.shade800,
      'approved' => Theme.of(context).colorScheme.primary,
      'completed' => Colors.green.shade700,
      'rejected' => Theme.of(context).colorScheme.error,
      _ => Theme.of(context).colorScheme.outline,
    };

String userName(dynamic user) {
  final map = asMap(user);
  final name = '${map['first_name'] ?? ''} ${map['last_name'] ?? ''}'.trim();
  return name.isEmpty ? (map['email']?.toString() ?? '') : name;
}

/// Aprobar, rechazar o eliminar un ajuste pendiente. Devuelve true si cambió.
Future<bool> runAdjustmentAction(BuildContext context, Map<String, dynamic> adjustment, String action) async {
  final number = adjustment['adjustment_number'] ?? '#${adjustment['id']}';
  final (title, message, verb, destructive) = switch (action) {
    'approve' => ('Aprobar ajuste', 'Las existencias se actualizarán al aprobar $number.', 'Aprobar', false),
    'reject' => ('Rechazar ajuste', 'El ajuste $number no modificará el inventario.', 'Rechazar', true),
    _ => ('Eliminar ajuste', '¿Seguro que deseas eliminar $number?', 'Eliminar', true),
  };
  if (!await confirm(context, title: title, message: message, action: verb, destructive: destructive) || !context.mounted) return false;
  try {
    final api = context.read<ApiClient>();
    action == 'delete'
        ? await api.delete('/inventory_adjustments/${adjustment['id']}')
        : await api.post('/inventory_adjustments/${adjustment['id']}/$action', {});
    if (context.mounted) {
      showMessage(context, switch (action) { 'approve' => 'Ajuste aprobado', 'reject' => 'Ajuste rechazado', _ => 'Ajuste eliminado' });
    }
    return true;
  } catch (error) {
    if (context.mounted) showError(context, error);
    return false;
  }
}

class AdjustmentsScreen extends StatefulWidget {
  const AdjustmentsScreen({super.key});

  @override
  State<AdjustmentsScreen> createState() => _AdjustmentsScreenState();
}

class _AdjustmentsScreenState extends State<AdjustmentsScreen> {
  late Future<List<Map<String, dynamic>>> _future = _load();
  String? _status;

  Future<List<Map<String, dynamic>>> _load() async => asMapList(await context.read<ApiClient>().get('/inventory_adjustments'));

  void _reload() => setState(() => _future = _load());

  @override
  Widget build(BuildContext context) {
    return ModuleScaffold(
      title: 'Ajustes de inventario',
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () async {
          final created = await context.push<bool>('/inventory-adjustments/new');
          if (created == true) _reload();
        },
        icon: const Icon(Icons.add),
        label: const Text('Nuevo ajuste'),
      ),
      body: FutureBuilder<List<Map<String, dynamic>>>(
        future: _future,
        builder: (context, snapshot) {
          if (snapshot.connectionState != ConnectionState.done) return const LoadingView();
          if (snapshot.hasError) return ErrorView(error: snapshot.error!, onRetry: _reload);
          final items = snapshot.data!.where((a) => _status == null || a['status'] == _status).toList();
          return RefreshIndicator(
            onRefresh: () async => _reload(),
            child: ListView(padding: const EdgeInsets.fromLTRB(16, 8, 16, 96), children: [
              SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: Row(children: [
                  for (final entry in {null: 'Todos', ...adjustmentStatusLabels}.entries)
                    Padding(
                      padding: const EdgeInsets.only(right: 8),
                      child: ChoiceChip(label: Text(entry.value), selected: _status == entry.key, onSelected: (_) => setState(() => _status = entry.key)),
                    ),
                ]),
              ),
              const SizedBox(height: 8),
              if (items.isEmpty)
                const MessageView(icon: Icons.tune, title: 'Sin ajustes', message: 'Registra unidades que necesitas agregar o retirar de tus almacenes.'),
              for (final a in items)
                Card(
                  margin: const EdgeInsets.only(bottom: 8),
                  child: ListTile(
                    title: Text(a['adjustment_number']?.toString() ?? 'Ajuste #${a['id']}'),
                    subtitle: Text('${formatDate(a['adjustment_date'])} · ${asMapList(a['adjustment_items']).length} productos\n${userName(a['created_by_user'])}'),
                    isThreeLine: true,
                    trailing: Column(mainAxisAlignment: MainAxisAlignment.center, crossAxisAlignment: CrossAxisAlignment.end, children: [
                      StatusChip(adjustmentStatusLabels[a['status']] ?? '${a['status']}', color: adjustmentStatusColor(context, a['status']?.toString())),
                    ]),
                    onTap: () async {
                      final changed = await context.push<bool>('/inventory-adjustments/${a['id']}');
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
