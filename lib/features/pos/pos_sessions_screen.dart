import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/api_client.dart';
import '../../core/formatters.dart';
import '../../core/user_profile.dart';
import '../../widgets/app_shell.dart';
import '../../widgets/async_states.dart';
import '../../widgets/form_fields.dart';
import 'pos_models.dart';

/// Mis últimos cortes de caja (GET /pos/sessions).
class PosSessionsScreen extends StatefulWidget {
  const PosSessionsScreen({super.key});

  @override
  State<PosSessionsScreen> createState() => _PosSessionsScreenState();
}

class _PosSessionsScreenState extends State<PosSessionsScreen> {
  late Future<List<Map<String, dynamic>>> _future = _load();

  Future<List<Map<String, dynamic>>> _load() async => asMapList(await context.read<ApiClient>().get('/pos/sessions'));

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return ModuleScaffold(
      title: 'Cortes',
      body: FutureBuilder<List<Map<String, dynamic>>>(
        future: _future,
        builder: (context, snapshot) {
          if (snapshot.connectionState != ConnectionState.done) return const LoadingView();
          if (snapshot.hasError) return ErrorView(error: snapshot.error!, onRetry: () => setState(() => _future = _load()));
          final sessions = snapshot.data!;
          return RefreshIndicator(
            onRefresh: () async => setState(() => _future = _load()),
            child: ListView(padding: const EdgeInsets.all(16), children: [
              if (sessions.isEmpty) const MessageView(icon: Icons.fact_check_outlined, title: 'Sin cortes', message: 'Aquí aparecerán tus cajas abiertas y cerradas.'),
              for (final s in sessions)
                Card(
                  margin: const EdgeInsets.only(bottom: 8),
                  child: Padding(
                    padding: const EdgeInsets.only(bottom: 8),
                    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      ListTile(
                        title: Text('Caja #${s['id']} · ${s['warehouse_name'] ?? ''}'),
                        subtitle: Text('Abierta ${formatDateTime(s['created_at'])}${s['closed_at'] != null ? '\nCerrada ${formatDateTime(s['closed_at'])}' : ''}'),
                        trailing: StatusChip(s['closed_at'] == null ? 'Abierta' : 'Cerrada', color: s['closed_at'] == null ? Colors.green.shade700 : theme.colorScheme.outline),
                      ),
                      InfoRow('Fondo', money(s['opening_amount'])),
                      InfoRow('Efectivo', money(asMap(s['totals'])['cash'])),
                      InfoRow('Tarjeta', money(asMap(s['totals'])['card'])),
                      InfoRow('Transferencia', money(asMap(s['totals'])['transfer'])),
                      InfoRow('Efectivo esperado', money(s['expected_amount'] ?? s['cash_expected'])),
                      if (s['counted_amount'] != null) InfoRow('Contado', money(s['counted_amount'])),
                      if (s['difference'] != null) InfoRow('Diferencia', money(s['difference'])),
                    ]),
                  ),
                ),
            ]),
          );
        },
      ),
    );
  }
}
