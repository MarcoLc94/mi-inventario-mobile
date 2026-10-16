import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../core/api_client.dart';
import '../../core/formatters.dart';
import '../../core/play_billing.dart';
import '../../core/session.dart';
import '../../core/user_profile.dart';
import '../../widgets/app_shell.dart';
import '../../widgets/async_states.dart';
import '../../widgets/form_fields.dart';

const _statusLabels = {
  'pending': 'Sin plan',
  'trial': 'Periodo de prueba',
  'active': 'Activa',
  'past_due': 'Pago pendiente',
  'suspended': 'Suspendida',
  'cancelled': 'Cancelada',
};
const _planLabels = {'free': 'Plan gratuito', 'trial': 'Prueba gratuita', 'monthly': 'Plan mensual', 'annual': 'Plan anual'};

/// Plan y suscripción. En la app el cobro es solo con Google Play Billing; no
/// se muestran precios ni enlaces de pago externos (políticas de Play).
class BillingScreen extends StatefulWidget {
  const BillingScreen({super.key, this.title = 'Plan y suscripción'});
  final String title;

  @override
  State<BillingScreen> createState() => _BillingScreenState();
}

class _BillingScreenState extends State<BillingScreen> {
  late final PlayBilling _play = PlayBilling(context.read<ApiClient>());
  Map<String, dynamic>? _billing;
  Object? _error;
  bool _trialBusy = false;

  @override
  void initState() {
    super.initState();
    _play.onVerified = _reload;
    _play.addListener(_rebuild);
    _load();
    _play.start();
  }

  @override
  void dispose() {
    _play.removeListener(_rebuild);
    _play.dispose();
    super.dispose();
  }

  void _rebuild() {
    if (mounted) setState(() {});
  }

  Future<void> _load() async {
    try {
      final data = asMap(await context.read<ApiClient>().get('/billing'));
      if (mounted) setState(() => _billing = data);
    } catch (error) {
      if (mounted) setState(() => _error = error);
    }
  }

  Future<void> _reload() async {
    await _load();
    if (mounted) await context.read<SessionController>().reloadProfile().catchError((_) {});
  }

  Future<void> _startTrial() async {
    setState(() => _trialBusy = true);
    try {
      final data = asMap(await context.read<ApiClient>().post('/billing/select_trial', {}));
      if (!mounted) return;
      setState(() => _billing = data);
      showMessage(context, 'Tu prueba gratuita está activa.');
      await context.read<SessionController>().reloadProfile().catchError((_) {});
    } catch (error) {
      if (mounted) showError(context, error);
    } finally {
      if (mounted) setState(() => _trialBusy = false);
    }
  }

  void _manageInPlay(String? productId) => launchUrl(
        Uri.parse('https://play.google.com/store/account/subscriptions?package=$playPackage${productId != null ? '&sku=$productId' : ''}'),
        mode: LaunchMode.externalApplication,
      );

  @override
  Widget build(BuildContext context) {
    final b = _billing;
    final user = context.watch<SessionController>().profile;
    Widget body;
    if (b == null) {
      body = _error != null ? ErrorView(error: _error!, onRetry: _load) : const LoadingView();
    } else {
      final theme = Theme.of(context);
      final status = b['status']?.toString();
      final provider = b['billing_provider']?.toString();
      final active = b['subscription_active'] == true;
      final paidPlan = (status == 'active' || status == 'past_due') && (b['plan'] == 'monthly' || b['plan'] == 'annual');
      final paidWithStripe = paidPlan && provider != 'google_play';
      final paidWithPlay = paidPlan && provider == 'google_play';
      final isAdmin = user?.isAdmin ?? false;
      final trialEnds = parseDate(b['trial_ends_at']);
      final canTrial = status == 'pending' && b['trial_available'] == true;
      body = RefreshIndicator(
        onRefresh: _load,
        child: ListView(padding: const EdgeInsets.all(16), children: [
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text('TU PLAN ACTUAL', style: theme.textTheme.labelSmall?.copyWith(color: theme.colorScheme.primary, letterSpacing: 1.1)),
                const SizedBox(height: 4),
                Text(_planLabels[b['plan']] ?? 'Sin plan', style: theme.textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w700)),
                const SizedBox(height: 4),
                StatusChip(_statusLabels[status] ?? status ?? '', color: active ? Colors.green.shade700 : theme.colorScheme.error),
                const SizedBox(height: 8),
                if (status == 'trial' && trialEnds != null) Text('La prueba termina el ${formatDate(b['trial_ends_at'])}.'),
                if (paidPlan && b['current_period_end'] != null)
                  Text('${status == 'past_due' ? 'Pago pendiente. ' : ''}Periodo actual hasta el ${formatDate(b['current_period_end'])}.'),
                if (b['plan'] == 'free')
                  const Text('Incluye Inventario para 1 usuario, 1 almacén y hasta 50 productos. '
                      'Suscríbete para quitar los límites y activar Compras, Ventas y Punto de venta.'),
                if (paidWithPlay) const Text('Se cobra con Google Play.'),
                if (paidWithStripe) const Text('Tu suscripción ya está activa y se administra desde tu cuenta en la web.'),
              ]),
            ),
          ),
          const SizedBox(height: 12),
          if (_play.message != null) _Banner(_play.message!, theme.colorScheme.secondaryContainer),
          if (_play.error != null) _Banner(_play.error!, theme.colorScheme.errorContainer),
          if (paidWithPlay)
            OutlinedButton.icon(
              onPressed: () => _manageInPlay(b['google_play_product_id']?.toString()),
              icon: const Icon(Icons.open_in_new),
              label: const Text('Administrar en Google Play'),
            ),
          if (!paidPlan && !isAdmin)
            const _Banner('Pide al administrador de tu empresa que active un plan para seguir usando Mi Inventario.', null),
          if (!paidPlan && isAdmin) ...[
            if (canTrial) ...[
              FilledButton.tonalIcon(
                onPressed: _trialBusy ? null : _startTrial,
                icon: const Icon(Icons.card_giftcard),
                label: Text(_trialBusy ? 'Activando…' : 'Probar 14 días gratis'),
              ),
              const SizedBox(height: 16),
            ],
            Text('Suscríbete con Google Play', style: theme.textTheme.titleMedium),
            const SizedBox(height: 8),
            if (_play.loading) const Padding(padding: EdgeInsets.all(24), child: Center(child: CircularProgressIndicator())),
            for (final id in ['mi_inventario_mensual', 'mi_inventario_anual'])
              if (_play.products[id] case final product?)
                Builder(builder: (context) {
                  final price = _play.priceOf(product);
                  return Card(
                    margin: const EdgeInsets.only(bottom: 8),
                    child: ListTile(
                      contentPadding: const EdgeInsets.all(16),
                      title: Text(id == 'mi_inventario_anual' ? 'Plan anual' : 'Plan mensual', style: theme.textTheme.titleMedium),
                      subtitle: Text([
                        '${price.price} ${id == 'mi_inventario_anual' ? 'al año' : 'al mes'}',
                        ?price.intro,
                        'Se renueva automáticamente. Cancela cuando quieras en Google Play.',
                      ].join('\n')),
                      isThreeLine: true,
                      trailing: FilledButton(
                        onPressed: _play.busy || user?.account['id'] == null ? null : () => _play.buy(product, accountId: (user!.account['id'] as num).toInt()),
                        child: const Text('Suscribirme'),
                      ),
                    ),
                  );
                }),
            const SizedBox(height: 8),
            TextButton(
              onPressed: _play.busy || user?.account['id'] == null ? null : () => _play.restore(accountId: (user!.account['id'] as num).toInt()),
              child: const Text('Ya pagué en Google Play: restaurar compra'),
            ),
          ],
          const SizedBox(height: 24),
        ]),
      );
    }
    return ModuleScaffold(title: widget.title, body: body);
  }
}

class _Banner extends StatelessWidget {
  const _Banner(this.text, this.color);
  final String text;
  final Color? color;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(bottom: 12),
        child: Card(color: color, child: Padding(padding: const EdgeInsets.all(12), child: Text(text))),
      );
}
