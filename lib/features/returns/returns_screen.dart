import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../../core/api_client.dart';
import '../../core/formatters.dart';
import '../../core/user_profile.dart';
import '../../widgets/app_shell.dart';
import '../../widgets/async_states.dart';
import '../../widgets/status.dart';
import 'return_kind.dart';

class ReturnsScreen extends StatefulWidget {
  const ReturnsScreen({super.key, required this.kind});
  final ReturnKind kind;

  @override
  State<ReturnsScreen> createState() => _ReturnsScreenState();
}

class _ReturnsScreenState extends State<ReturnsScreen> {
  late Future<List<Map<String, dynamic>>> _future = _load();
  String? _status;

  Future<List<Map<String, dynamic>>> _load() async => asMapList(await context.read<ApiClient>().get(widget.kind.endpoint));
  void _reload() => setState(() => _future = _load());

  @override
  Widget build(BuildContext context) {
    final kind = widget.kind;
    return ModuleScaffold(
      title: kind.title,
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () async {
          final created = await context.push<bool>('${kind.basePath}/new');
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
          final items = snapshot.data!.where((r) => _status == null || r['status'] == _status).toList()
            ..sort((a, b) => '${b['created_at']}'.compareTo('${a['created_at']}'));
          return RefreshIndicator(
            onRefresh: () async => _reload(),
            child: ListView(padding: const EdgeInsets.fromLTRB(16, 8, 16, 96), children: [
              SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: Row(children: [
                  for (final entry in {null: 'Todas', ...returnStatus.labels}.entries)
                    Padding(
                      padding: const EdgeInsets.only(right: 8),
                      child: ChoiceChip(label: Text(entry.value), selected: _status == entry.key, onSelected: (_) => setState(() => _status = entry.key)),
                    ),
                ]),
              ),
              const SizedBox(height: 8),
              if (items.isEmpty) const MessageView(icon: Icons.keyboard_return, title: 'Sin devoluciones'),
              for (final r in items)
                Card(
                  margin: const EdgeInsets.only(bottom: 8),
                  child: ListTile(
                    title: Text(r['return_number']?.toString() ?? 'Devolución #${r['id']}'),
                    subtitle: Text('${kind.partnerName(r)}\n${kind.documentLabel} ${kind.document(r)['order_number'] ?? '—'} · ${formatDate(r['return_date'])}'),
                    isThreeLine: true,
                    trailing: Column(mainAxisAlignment: MainAxisAlignment.center, crossAxisAlignment: CrossAxisAlignment.end, children: [
                      Text(formatMoney(r[kind.totalKey]), style: Theme.of(context).textTheme.titleSmall),
                      returnStatus.chip(context, r['status']),
                    ]),
                    onTap: () async {
                      final changed = await context.push<bool>('${kind.basePath}/${r['id']}');
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
