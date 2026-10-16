import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../../core/api_client.dart';
import '../../core/formatters.dart';
import '../../core/user_profile.dart';
import '../../core/theme.dart';
import '../../widgets/app_shell.dart';
import '../../widgets/boxy_face.dart';

class _Message {
  _Message(this.role, this.content, {this.products = const [], this.checkedAt});
  final String role;
  final String content;
  final List<Map<String, dynamic>> products;
  final String? checkedAt;
}

/// Chat con Boxy (POST /boxy/chat): explica cómo usar la plataforma y consulta
/// los productos que el usuario tiene permiso de ver. No modifica nada.
class BoxyScreen extends StatefulWidget {
  const BoxyScreen({super.key});

  @override
  State<BoxyScreen> createState() => _BoxyScreenState();
}

class _BoxyScreenState extends State<BoxyScreen> {
  final _messages = <_Message>[];
  final _input = TextEditingController();
  final _scroll = ScrollController();
  bool _busy = false;
  String? _error;

  static const _suggestions = ['¿Cómo registro una entrada manual?', '¿Qué productos están agotados?', '¿Dónde descargo mis comprobantes?'];

  @override
  void dispose() {
    _input.dispose();
    _scroll.dispose();
    super.dispose();
  }

  Future<void> _send([String? preset]) async {
    final text = (preset ?? _input.text).trim();
    if (text.isEmpty || _busy) return;
    final history = _messages.reversed.take(10).toList().reversed.map((m) => {'role': m.role, 'content': m.content}).toList();
    setState(() {
      _busy = true;
      _error = null;
      _messages.add(_Message('user', text));
      _input.clear();
    });
    _scrollDown();
    try {
      final reply = asMap(await context.read<ApiClient>().post('/boxy/chat', {'message': text, 'history': history}));
      final inventory = asMap(reply['inventory']);
      if (mounted) {
        setState(
          () => _messages.add(
            _Message(
              'assistant',
              reply['message']?.toString() ?? '',
              products: asMapList(inventory['products']),
              checkedAt: inventory['checked_at']?.toString(),
            ),
          ),
        );
      }
    } catch (error) {
      if (mounted) {
        setState(() {
          _messages.removeLast();
          _input.text = text;
          _error = error.toString();
        });
      }
    } finally {
      if (mounted) setState(() => _busy = false);
      _scrollDown();
    }
  }

  void _scrollDown() => WidgetsBinding.instance.addPostFrameCallback((_) {
    if (_scroll.hasClients) {
      _scroll.animateTo(_scroll.position.maxScrollExtent, duration: const Duration(milliseconds: 250), curve: Curves.easeOut);
    }
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return ModuleScaffold(
      title: 'Boxy',
      actions: [
        IconButton(
          tooltip: 'Nueva conversación',
          onPressed: _busy || _messages.isEmpty ? null : () => setState(() => _messages.clear()),
          icon: const Icon(Icons.restart_alt),
        ),
      ],
      body: Column(
        children: [
          Expanded(
            child: ListView(
              controller: _scroll,
              padding: const EdgeInsets.all(16),
              children: [
                if (_messages.isEmpty) ...[
                  const SizedBox(height: 24),
                  const Center(child: BoxyFace(size: 110)),
                  const SizedBox(height: 8),
                  Text('¡Hola! ¿Qué necesitas?', style: theme.textTheme.headlineSmall, textAlign: TextAlign.center),
                  const Text(
                    'Puedo explicarte cómo usar la plataforma y consultar los productos que tienes permiso de ver.',
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 16),
                  for (final s in _suggestions)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 8),
                      child: OutlinedButton(onPressed: () => _send(s), child: Text(s)),
                    ),
                ],
                for (final m in _messages)
                  Row(
                    mainAxisAlignment: m.role == 'user' ? MainAxisAlignment.end : MainAxisAlignment.start,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      if (m.role != 'user')
                        const Padding(padding: EdgeInsets.only(right: 6, top: 2), child: BoxyFace(size: 34, animate: false)),
                      Container(
                        constraints: BoxConstraints(maxWidth: MediaQuery.of(context).size.width * .82),
                        margin: const EdgeInsets.only(bottom: 10),
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: m.role == 'user' ? context.mi.primary : context.mi.surface,
                          border: m.role == 'user' ? null : Border.all(color: context.mi.border),
                          borderRadius: BorderRadius.circular(16),
                        ),
                        child: DefaultTextStyle.merge(
                          style: TextStyle(color: m.role == 'user' ? Colors.white : context.mi.text),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                m.role == 'user' ? 'Tú' : 'Boxy',
                                style: theme.textTheme.labelSmall?.copyWith(color: m.role == 'user' ? Colors.white70 : context.mi.muted),
                              ),
                              const SizedBox(height: 2),
                              SelectableText(m.content),
                              if (m.products.isNotEmpty) ...[
                                const SizedBox(height: 8),
                                Text(
                                  'Datos consultados ${m.checkedAt == null ? '' : formatDateTime(m.checkedAt)}',
                                  style: theme.textTheme.labelSmall,
                                ),
                                for (final p in m.products)
                                  ListTile(
                                    dense: true,
                                    contentPadding: EdgeInsets.zero,
                                    title: Text(p['name']?.toString() ?? ''),
                                    subtitle: Text(
                                      [
                                        'Stock total: ${formatNumber(p['stock'])}',
                                        for (final w in asMapList(p['warehouses']))
                                          '${w['name']}: ${formatNumber(w['available'])} disponibles',
                                      ].join('\n'),
                                    ),
                                    onTap: () => context.push('/products/${p['id']}'),
                                  ),
                              ],
                            ],
                          ),
                        ),
                      ),
                    ],
                  ),
                if (_busy)
                  const Padding(
                    padding: EdgeInsets.all(8),
                    child: Row(children: [BoxyFace(size: 34, speaking: true), SizedBox(width: 8), Text('Boxy está consultando…')]),
                  ),
              ],
            ),
          ),
          if (_error != null)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Text(_error!, style: TextStyle(color: theme.colorScheme.error)),
            ),
          SafeArea(
            top: false,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(12, 8, 12, 12),
              child: Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: _input,
                      maxLength: 1500,
                      minLines: 1,
                      maxLines: 4,
                      enabled: !_busy,
                      textInputAction: TextInputAction.send,
                      onSubmitted: (_) => _send(),
                      decoration: const InputDecoration(
                        hintText: 'Pregunta sobre tus productos o cómo usar Mi Inventario…',
                        counterText: '',
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  IconButton.filled(tooltip: 'Enviar', onPressed: _busy ? null : _send, icon: const Icon(Icons.send)),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
