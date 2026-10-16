import 'dart:async';

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
import '../users/users_screen.dart';

const _accountStatus = {
  'pending': 'Sin plan',
  'trial': 'Prueba',
  'active': 'Activa',
  'past_due': 'Pago atrasado',
  'suspended': 'Suspendida',
  'cancelled': 'Cancelada',
};
const _platformModules = {'pos': 'Punto de venta', 'invoicing': 'Facturación'};

/// Backoffice de la plataforma (solo usuarios con ese permiso): empresas,
/// actividad, prueba gratuita y módulos, y la bandeja de sugerencias.
class BackofficeScreen extends StatefulWidget {
  const BackofficeScreen({super.key});

  @override
  State<BackofficeScreen> createState() => _BackofficeScreenState();
}

class _BackofficeScreenState extends State<BackofficeScreen> {
  final _listKey = GlobalKey<PagedListState>();
  String _query = '';
  String? _status;
  Map<String, dynamic> _summary = {};
  Timer? _debounce;

  @override
  void dispose() {
    _debounce?.cancel();
    super.dispose();
  }

  Future<PageResult> _fetch(int page) async {
    final data = asMap(await context.read<ApiClient>().get('/platform_admin', query: {'q': _query, 'status': _status, 'page': page}));
    if (mounted) setState(() => _summary = asMap(data['summary']));
    return PageResult(asMapList(data['data']), (data['total'] as num?)?.toInt() ?? 0, (data['total_pages'] as num?)?.toInt() ?? 1);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final statuses = asMap(_summary['statuses']);
    return ModuleScaffold(
      title: 'Backoffice',
      actions: [
        IconButton(tooltip: 'Sugerencias', onPressed: () => context.push('/platform-admin/suggestions'), icon: const Icon(Icons.lightbulb_outline)),
      ],
      body: PagedList(
        key: _listKey,
        queryKey: (_query, _status),
        fetch: _fetch,
        emptyIcon: Icons.business_outlined,
        emptyTitle: 'Sin empresas',
        header: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Row(children: [
            _Stat('Empresas', formatNumber(_summary['accounts'] ?? 0)),
            const SizedBox(width: 8),
            _Stat('Este mes', formatNumber(_summary['registered_this_month'] ?? 0)),
            const SizedBox(width: 8),
            _Stat('Activas', formatNumber(statuses['active'] ?? 0)),
          ]),
          const SizedBox(height: 8),
          TextField(
            onChanged: (v) {
              _debounce?.cancel();
              _debounce = Timer(const Duration(milliseconds: 400), () => setState(() => _query = v.trim()));
            },
            decoration: const InputDecoration(hintText: 'Buscar empresa', prefixIcon: Icon(Icons.search)),
          ),
          const SizedBox(height: 8),
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(children: [
              for (final entry in {null: 'Todas', ..._accountStatus}.entries)
                Padding(
                  padding: const EdgeInsets.only(right: 8),
                  child: ChoiceChip(
                    label: Text(entry.key == null ? entry.value : '${entry.value} (${statuses[entry.key] ?? 0})'),
                    selected: _status == entry.key,
                    onSelected: (_) => setState(() => _status = entry.key),
                  ),
                ),
            ]),
          ),
          const SizedBox(height: 8),
        ]),
        itemBuilder: (context, account, reload) => Card(
          margin: const EdgeInsets.only(bottom: 8),
          child: ListTile(
            title: Text(account['name']?.toString() ?? ''),
            subtitle: Text([
              '#${account['id']} · ${account['plan'] ?? 'Sin plan'} · alta ${formatDate(account['created_at'])}',
              'Actividad: ${formatDateTime(account['last_seen_at'] ?? account['last_login_at'])}',
            ].join('\n')),
            isThreeLine: true,
            trailing: StatusChip(_accountStatus[account['status']] ?? '${account['status']}',
                color: account['subscription_active'] == false ? theme.colorScheme.error : Colors.green.shade700),
            onTap: () async {
              final changed = await Navigator.of(context).push<bool>(MaterialPageRoute(builder: (_) => _AccountManage(account: account)));
              if (changed == true) reload();
            },
          ),
        ),
      ),
    );
  }
}

class _Stat extends StatelessWidget {
  const _Stat(this.label, this.value);
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) => Expanded(
        child: Card(
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(label, style: Theme.of(context).textTheme.labelSmall),
              Text(value, style: Theme.of(context).textTheme.titleLarge),
            ]),
          ),
        ),
      );
}

class _AccountManage extends StatefulWidget {
  const _AccountManage({required this.account});
  final Map<String, dynamic> account;

  @override
  State<_AccountManage> createState() => _AccountManageState();
}

class _AccountManageState extends State<_AccountManage> {
  late Map<String, dynamic> _a = widget.account;
  final _trialDays = TextEditingController(text: '14');
  final _moduleDays = {for (final k in _platformModules.keys) k: TextEditingController(text: '30')};
  String? _busy;
  bool _changed = false;

  Future<void> _run(String key, Future<dynamic> Function() action, String success) async {
    setState(() => _busy = key);
    try {
      final updated = asMap(await action());
      if (!mounted) return;
      setState(() {
        _a = {..._a, ...updated};
        _changed = true;
      });
      showMessage(context, success);
    } catch (error) {
      if (mounted) showError(context, error);
    } finally {
      if (mounted) setState(() => _busy = null);
    }
  }

  @override
  Widget build(BuildContext context) {
    final api = context.read<ApiClient>();
    final modules = asMap(_a['modules']);
    final usage = asMap(_a['usage']);
    final limits = asMap(_a['limits']);
    final canExtend = _a['status'] == 'pending' || _a['status'] == 'trial';
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) Navigator.of(context).pop(_changed);
      },
      child: Scaffold(
        appBar: AppBar(title: Text(_a['name']?.toString() ?? 'Empresa')),
        body: ListView(padding: const EdgeInsets.all(16), children: [
          if (_a['subscription_active'] == false)
            Card(
              color: Theme.of(context).colorScheme.errorContainer,
              child: const Padding(padding: EdgeInsets.all(12), child: Text('Sin prueba ni suscripción vigente: los módulos no funcionan hasta ampliar la prueba.')),
            ),
          SectionCard(title: 'Suscripción', children: [
            InfoRow('Estado', _accountStatus[_a['status']] ?? _a['status']?.toString()),
            InfoRow('Plan', _a['plan']?.toString() ?? 'Sin plan'),
            InfoRow('Fin de prueba', formatDate(_a['trial_ends_at'])),
            InfoRow('Fin de periodo', formatDate(_a['current_period_end'])),
          ]),
          const SizedBox(height: 12),
          SectionCard(title: 'Uso de recursos', children: [
            for (final (key, label) in const [('users', 'Usuarios'), ('products', 'Productos'), ('warehouses', 'Almacenes')])
              InfoRow(label, '${formatNumber(usage[key] ?? 0)} / ${limits[key] == null ? 'Sin límite' : formatNumber(limits[key])}'),
          ]),
          const SizedBox(height: 12),
          SectionCard(title: 'Prueba gratuita', children: [
            if (!canExtend)
              const Padding(padding: EdgeInsets.fromLTRB(16, 0, 16, 8), child: Text('Solo se amplía la prueba de empresas sin plan o en prueba.'))
            else
              Padding(
                padding: const EdgeInsets.all(16),
                child: Row(children: [
                  Expanded(child: TextField(controller: _trialDays, keyboardType: TextInputType.number, decoration: const InputDecoration(labelText: 'Días a agregar'))),
                  const SizedBox(width: 8),
                  FilledButton(
                    onPressed: _busy != null
                        ? null
                        : () => _run('trial', () => api.patch('/platform_admin/accounts/${_a['id']}/trial', {'days': int.tryParse(_trialDays.text) ?? 0}),
                            'Prueba ampliada ${_trialDays.text} días.'),
                    child: Text(_busy == 'trial' ? 'Guardando…' : 'Ampliar'),
                  ),
                ]),
              ),
          ]),
          const SizedBox(height: 12),
          SectionCard(title: 'Módulos', children: [
            for (final entry in _platformModules.entries)
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
                child: Row(children: [
                  Expanded(child: Text('${entry.value}: ${modules[entry.key] == true ? 'activo' : 'inactivo'}')),
                  if (modules[entry.key] != true) ...[
                    SizedBox(width: 70, child: TextField(controller: _moduleDays[entry.key], keyboardType: TextInputType.number, decoration: const InputDecoration(labelText: 'Días'))),
                    const SizedBox(width: 8),
                  ],
                  FilledButton.tonal(
                    onPressed: _busy != null
                        ? null
                        : () {
                            final enable = modules[entry.key] != true;
                            _run(entry.key, () => api.patch('/platform_admin/accounts/${_a['id']}/modules', {
                                  'module': entry.key,
                                  'enabled': enable,
                                  if (enable) 'days': int.tryParse(_moduleDays[entry.key]!.text) ?? 30,
                                }), enable ? '${entry.value} habilitado.' : '${entry.value} deshabilitado.');
                          },
                    child: Text(modules[entry.key] == true ? 'Deshabilitar' : 'Habilitar'),
                  ),
                ]),
              ),
          ]),
          const SizedBox(height: 12),
          SectionCard(title: 'Usuarios', children: [
            for (final u in asMapList(_a['users']))
              ListTile(
                dense: true,
                title: Text(u['name']?.toString() ?? ''),
                subtitle: Text('${u['email'] ?? ''}\n${roleLabels[u['role']] ?? u['role']} · actividad ${formatDateTime(u['last_seen_at'] ?? u['last_login_at'])}'),
                isThreeLine: true,
              ),
          ]),
          const SizedBox(height: 24),
        ]),
      ),
    );
  }
}
