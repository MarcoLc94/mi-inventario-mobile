import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../../core/formatters.dart';
import '../../core/push.dart';
import '../../core/theme.dart';
import '../../widgets/async_states.dart';

const _kinds = {
  'stock': (Icons.inventory_2_outlined, 'Inventario'),
  'orders': (Icons.local_shipping_outlined, 'Órdenes'),
  'lots': (Icons.event_busy_outlined, 'Lotes'),
  'cash': (Icons.point_of_sale_outlined, 'Caja'),
  'billing': (Icons.workspace_premium_outlined, 'Plan'),
};

/// Avisos: stock bajo, órdenes por vencer, lotes por caducar, caja sin corte
/// y plan. Son los mismos que llegan como notificación push.
class NotificationsScreen extends StatefulWidget {
  const NotificationsScreen({super.key});

  @override
  State<NotificationsScreen> createState() => _NotificationsScreenState();
}

class _NotificationsScreenState extends State<NotificationsScreen> {
  @override
  void initState() {
    super.initState();
    context.read<PushService>().refresh();
  }

  @override
  Widget build(BuildContext context) {
    final push = context.watch<PushService>();
    final mi = context.mi;
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(
        title: const Text('Avisos'),
        actions: [
          if (push.unread > 0) TextButton(onPressed: () => push.markRead(), child: const Text('Marcar todo leído')),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: push.refresh,
        child: push.notices.isEmpty
            ? ListView(children: [
                SizedBox(
                  height: 420,
                  child: push.loading
                      ? const LoadingView()
                      : const MessageView(
                          icon: Icons.notifications_none,
                          title: 'Sin avisos',
                          message: 'Aquí verás el stock bajo, las órdenes por vencer, los lotes por caducar y los avisos de tu plan.',
                        ),
                ),
              ])
            : ListView.separated(
                padding: const EdgeInsets.all(12),
                itemCount: push.notices.length,
                separatorBuilder: (_, _) => const SizedBox(height: 8),
                itemBuilder: (context, index) {
                  final notice = push.notices[index];
                  final (icon, label) = _kinds[notice.kind] ?? (Icons.notifications_none, 'Aviso');
                  final warn = notice.title.startsWith('Agotado') || notice.kind == 'billing';
                  final color = warn ? mi.danger : mi.primary;
                  return Card(
                    color: notice.read ? null : Color.alphaBlend(mi.primary.withValues(alpha: .05), mi.surface),
                    child: InkWell(
                      borderRadius: BorderRadius.circular(14),
                      onTap: () {
                        push.markRead(notice);
                        if (notice.path?.isNotEmpty ?? false) context.push(notice.path!);
                      },
                      child: Padding(
                        padding: const EdgeInsets.all(14),
                        child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                          Container(
                            width: 40,
                            height: 40,
                            decoration: BoxDecoration(color: color.withValues(alpha: .12), borderRadius: BorderRadius.circular(10)),
                            child: Icon(icon, color: color, size: 21),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                              Row(children: [
                                Text(label.toUpperCase(), style: eyebrow(context, color: color)),
                                const Spacer(),
                                if (notice.createdAt != null) Text(formatDateTime(notice.createdAt!.toIso8601String()), style: theme.textTheme.bodySmall),
                              ]),
                              const SizedBox(height: 2),
                              Text(notice.title, style: theme.textTheme.titleSmall?.copyWith(fontWeight: notice.read ? FontWeight.w500 : FontWeight.w700)),
                              const SizedBox(height: 2),
                              Text(notice.body, style: theme.textTheme.bodyMedium?.copyWith(color: mi.muted)),
                            ]),
                          ),
                          if (!notice.read)
                            Container(
                              margin: const EdgeInsets.only(left: 8, top: 4),
                              width: 9,
                              height: 9,
                              decoration: BoxDecoration(color: mi.primary, shape: BoxShape.circle),
                            ),
                        ]),
                      ),
                    ),
                  );
                },
              ),
      ),
    );
  }
}
