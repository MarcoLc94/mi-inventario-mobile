import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../../core/api_client.dart';
import '../../core/formatters.dart';
import '../../core/user_profile.dart';
import '../../widgets/app_shell.dart';
import '../../widgets/async_states.dart';
import '../../widgets/form_fields.dart';
import '../../widgets/paged_list.dart';

const suggestionStatus = {'open': 'Abierto', 'in_progress': 'Atendiendo', 'resolved': 'Resuelto', 'closed': 'Cerrado'};
const _transitions = {
  'open': ['in_progress', 'closed'],
  'in_progress': ['resolved', 'closed'],
  'resolved': ['closed'],
  'closed': <String>[],
};

Color suggestionColor(BuildContext context, String? status) => switch (status) {
      'open' => Colors.orange.shade800,
      'in_progress' => Theme.of(context).colorScheme.primary,
      'resolved' => Colors.green.shade700,
      _ => Theme.of(context).colorScheme.outline,
    };

/// Sugerencias y soporte. Con [backoffice] es la bandeja de la plataforma:
/// ve las de todas las empresas y cambia su estado.
class SuggestionsScreen extends StatefulWidget {
  const SuggestionsScreen({super.key, this.backoffice = false});
  final bool backoffice;

  @override
  State<SuggestionsScreen> createState() => _SuggestionsScreenState();
}

class _SuggestionsScreenState extends State<SuggestionsScreen> {
  final _listKey = GlobalKey<PagedListState>();
  String? _status;

  String get _api => widget.backoffice ? '/platform_admin/suggestions' : '/suggestions';
  String get _root => widget.backoffice ? '/platform-admin/suggestions' : '/help/suggestions';

  Future<void> _create() async {
    final created = await showModalBottomSheet<Map<String, dynamic>>(context: context, isScrollControlled: true, useSafeArea: true, builder: (_) => const _NewSuggestion());
    if (created != null && mounted) {
      _listKey.currentState?.reload();
      context.push('$_root/${created['id']}');
    }
  }

  @override
  Widget build(BuildContext context) {
    return ModuleScaffold(
      title: widget.backoffice ? 'Sugerencias (Backoffice)' : 'Sugerencias',
      floatingActionButton: widget.backoffice ? null : FloatingActionButton.extended(onPressed: _create, icon: const Icon(Icons.add), label: const Text('Nueva')),
      body: PagedList(
        key: _listKey,
        queryKey: _status,
        fetch: (page) async {
          final data = asMap(await context.read<ApiClient>().get(_api, query: {'status': _status, 'page': page}));
          return PageResult(asMapList(data['data']), (data['total'] as num?)?.toInt() ?? 0, (data['total_pages'] as num?)?.toInt() ?? 1);
        },
        emptyIcon: Icons.lightbulb_outline,
        emptyTitle: 'Sin sugerencias',
        emptyMessage: widget.backoffice ? null : 'Cuéntanos qué mejorar o reporta un problema.',
        header: SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: Row(children: [
            for (final entry in {null: 'Todas', ...suggestionStatus}.entries)
              Padding(
                padding: const EdgeInsets.only(right: 8, bottom: 8),
                child: ChoiceChip(label: Text(entry.value), selected: _status == entry.key, onSelected: (_) => setState(() => _status = entry.key)),
              ),
          ]),
        ),
        itemBuilder: (context, t, reload) => Card(
          margin: const EdgeInsets.only(bottom: 8),
          child: ListTile(
            title: Text(t['title']?.toString() ?? ''),
            subtitle: Text([
              if (widget.backoffice) '${t['account_name'] ?? ''} · ${t['author_name'] ?? ''}' else t['author_name']?.toString() ?? '',
              'Actualizada ${formatDateTime(t['updated_at'])}',
            ].join('\n')),
            isThreeLine: true,
            trailing: StatusChip(suggestionStatus[t['status']] ?? '${t['status']}', color: suggestionColor(context, t['status']?.toString())),
            onTap: () async {
              await context.push('$_root/${t['id']}');
              reload();
            },
          ),
        ),
      ),
    );
  }
}

class _NewSuggestion extends StatefulWidget {
  const _NewSuggestion();

  @override
  State<_NewSuggestion> createState() => _NewSuggestionState();
}

class _NewSuggestionState extends State<_NewSuggestion> {
  final _title = TextEditingController();
  final _body = TextEditingController();
  bool _busy = false;
  String? _error;

  Future<void> _save() async {
    if (_title.text.trim().isEmpty || _body.text.trim().isEmpty) {
      setState(() => _error = 'Escribe un título y la descripción.');
      return;
    }
    setState(() => _busy = true);
    try {
      final created = await context.read<ApiClient>().post('/suggestions', {
        'suggestion': {'title': _title.text.trim(), 'body': _body.text.trim()},
      });
      if (mounted) Navigator.pop(context, asMap(created));
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
          Text('Nueva sugerencia', style: Theme.of(context).textTheme.titleLarge),
          const SizedBox(height: 12),
          if (_error != null) Text(_error!, style: TextStyle(color: Theme.of(context).colorScheme.error)),
          TextField(controller: _title, maxLength: 120, decoration: const InputDecoration(labelText: 'Título')),
          TextField(controller: _body, maxLines: 5, maxLength: 4000, decoration: const InputDecoration(labelText: '¿Qué te gustaría mejorar o qué problema tuviste?')),
          const SizedBox(height: 8),
          FilledButton(onPressed: _busy ? null : _save, child: Text(_busy ? 'Enviando…' : 'Enviar')),
        ]),
      );
}

/// Conversación de una sugerencia: mensajes, historial de estado y, en
/// Backoffice, cambio de estado.
class SuggestionDetailScreen extends StatefulWidget {
  const SuggestionDetailScreen({super.key, required this.id, this.backoffice = false});
  final String id;
  final bool backoffice;

  @override
  State<SuggestionDetailScreen> createState() => _SuggestionDetailScreenState();
}

class _SuggestionDetailScreenState extends State<SuggestionDetailScreen> {
  Map<String, dynamic>? _detail;
  final _messages = <int, Map<String, dynamic>>{};
  Object? _error;
  final _message = TextEditingController();
  bool _busy = false;

  String get _endpoint => '${widget.backoffice ? '/platform_admin/suggestions' : '/suggestions'}/${widget.id}';
  int get _lastId => _messages.keys.fold(0, (a, b) => a > b ? a : b);

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _message.dispose();
    super.dispose();
  }

  void _accept(Map<String, dynamic> data) {
    for (final m in asMapList(data['messages'])) {
      _messages[(m['id'] as num).toInt()] = m;
    }
    _detail = data;
  }

  Future<void> _load() async {
    try {
      final api = context.read<ApiClient>();
      var data = asMap(await api.get(_endpoint, query: {'after_message_id': _lastId}));
      _accept(data);
      // Conversaciones largas llegan por partes.
      for (var batch = 1; data['has_more_messages'] == true && batch < 20; batch++) {
        data = asMap(await api.get(_endpoint, query: {'after_message_id': _lastId}));
        _accept(data);
      }
      if (mounted) setState(() => _error = null);
    } catch (error) {
      if (mounted) setState(() => _error = error);
    }
  }

  Future<void> _send() async {
    final text = _message.text.trim();
    if (text.isEmpty) return;
    setState(() => _busy = true);
    try {
      final data = asMap(await context.read<ApiClient>().send('POST', '$_endpoint/message', query: {'after_message_id': _lastId}, body: {'body': text}));
      _accept(data);
      _message.clear();
      if (mounted) setState(() {});
    } catch (error) {
      if (mounted) showError(context, error);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _changeStatus(String target) async {
    final note = await promptText(context, title: 'Cambiar a ${suggestionStatus[target]}', label: 'Nota (opcional)', required: false, action: 'Guardar');
    if (note == null || !mounted) return;
    setState(() => _busy = true);
    try {
      final data = asMap(await context.read<ApiClient>().send('PATCH', _endpoint,
          query: {'after_message_id': _lastId}, body: {'status': target, 'expected_status': _detail!['status'], 'note': note}));
      _accept(data);
      if (mounted) setState(() {});
    } catch (error) {
      if (mounted) showError(context, error);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final d = _detail;
    final theme = Theme.of(context);
    if (d == null) {
      return Scaffold(appBar: AppBar(title: const Text('Sugerencia')), body: _error != null ? ErrorView(error: _error!, onRetry: _load) : const LoadingView());
    }
    final status = d['status']?.toString();
    final messages = _messages.values.toList()..sort((a, b) => (a['id'] as num).compareTo(b['id'] as num));
    final canWrite = status != 'closed';
    return Scaffold(
      appBar: AppBar(title: Text(d['title']?.toString() ?? 'Sugerencia')),
      body: Column(children: [
        Expanded(
          child: RefreshIndicator(
            onRefresh: _load,
            child: ListView(padding: const EdgeInsets.all(16), children: [
              Row(children: [
                StatusChip(suggestionStatus[status] ?? '$status', color: suggestionColor(context, status)),
                const Spacer(),
                Text(formatDateTime(d['created_at']), style: theme.textTheme.bodySmall),
              ]),
              const SizedBox(height: 8),
              Text('${d['author_name'] ?? ''}${widget.backoffice ? ' · ${d['account_name'] ?? ''}' : ''}', style: theme.textTheme.bodySmall),
              const SizedBox(height: 8),
              Card(child: Padding(padding: const EdgeInsets.all(12), child: SelectableText(d['body']?.toString() ?? ''))),
              if ((d['resolution']?.toString() ?? '').isNotEmpty) Card(color: Colors.green.shade50, child: Padding(padding: const EdgeInsets.all(12), child: Text('Resolución: ${d['resolution']}'))),
              if (widget.backoffice && (_transitions[status] ?? const []).isNotEmpty) ...[
                const SizedBox(height: 8),
                Wrap(spacing: 8, children: [
                  for (final target in _transitions[status]!)
                    OutlinedButton(onPressed: _busy ? null : () => _changeStatus(target), child: Text('Marcar ${suggestionStatus[target]!.toLowerCase()}')),
                ]),
              ],
              const SizedBox(height: 12),
              for (final m in messages)
                Align(
                  alignment: m['from_backoffice'] == true ? Alignment.centerLeft : Alignment.centerRight,
                  child: Container(
                    constraints: BoxConstraints(maxWidth: MediaQuery.of(context).size.width * .8),
                    margin: const EdgeInsets.only(bottom: 8),
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: m['from_backoffice'] == true ? theme.colorScheme.surfaceContainerHighest : theme.colorScheme.primaryContainer,
                      borderRadius: BorderRadius.circular(14),
                    ),
                    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Text('${m['author_name'] ?? ''}${m['from_backoffice'] == true ? ' · Soporte' : ''} · ${formatDateTime(m['created_at'])}', style: theme.textTheme.labelSmall),
                      const SizedBox(height: 2),
                      SelectableText(m['body']?.toString() ?? ''),
                    ]),
                  ),
                ),
              if (asMapList(d['events']).isNotEmpty) ...[
                const SizedBox(height: 12),
                SectionCard(title: 'Historial', children: [
                  for (final e in asMapList(d['events']))
                    ListTile(
                      dense: true,
                      title: Text(suggestionStatus[e['status']] ?? '${e['status']}'),
                      subtitle: Text('${e['author_name'] ?? ''} · ${formatDateTime(e['created_at'])}${(e['note']?.toString() ?? '').isNotEmpty ? '\n${e['note']}' : ''}'),
                    ),
                ]),
              ],
            ]),
          ),
        ),
        if (canWrite)
          SafeArea(
            top: false,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(12, 8, 12, 12),
              child: Row(children: [
                Expanded(child: TextField(controller: _message, minLines: 1, maxLines: 4, decoration: const InputDecoration(hintText: 'Escribe un mensaje'))),
                const SizedBox(width: 8),
                IconButton.filled(tooltip: 'Enviar', onPressed: _busy ? null : _send, icon: const Icon(Icons.send)),
              ]),
            ),
          ),
      ]),
    );
  }
}
