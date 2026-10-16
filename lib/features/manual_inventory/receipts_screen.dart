import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../../core/api_client.dart';
import '../../core/files.dart';
import '../../core/formatters.dart';
import '../../core/user_profile.dart';
import '../../widgets/app_shell.dart';
import '../../widgets/async_states.dart';

Future<void> openReceiptPdf(BuildContext context, Map<String, dynamic> receipt) async {
  try {
    await openRemotePdf(context.read<ApiClient>(), '/manual_inventory_movements/${receipt['id']}/receipt', '${receipt['folio'] ?? 'comprobante'}.pdf');
  } catch (error) {
    if (context.mounted) showError(context, error);
  }
}

/// Comprobantes de entradas y salidas manuales, con su PDF.
class ReceiptsScreen extends StatefulWidget {
  const ReceiptsScreen({super.key});

  @override
  State<ReceiptsScreen> createState() => _ReceiptsScreenState();
}

class _ReceiptsScreenState extends State<ReceiptsScreen> {
  late Future<List<Map<String, dynamic>>> _future = _load();

  Future<List<Map<String, dynamic>>> _load() async => asMapList(await context.read<ApiClient>().get('/manual_inventory_movements'));
  void _reload() => setState(() => _future = _load());

  Future<void> _new(String direction) async {
    final saved = await context.push<bool>('/inventory/manual?type=$direction');
    if (saved == true) _reload();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return ModuleScaffold(
      title: 'Comprobantes',
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => showModalBottomSheet<void>(
          context: context,
          builder: (sheet) => SafeArea(
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              ListTile(
                leading: Icon(Icons.south_west, color: Colors.green.shade700),
                title: const Text('Registrar entrada'),
                onTap: () {
                  Navigator.pop(sheet);
                  _new('IN');
                },
              ),
              ListTile(
                leading: Icon(Icons.north_east, color: theme.colorScheme.error),
                title: const Text('Registrar salida'),
                onTap: () {
                  Navigator.pop(sheet);
                  _new('OUT');
                },
              ),
            ]),
          ),
        ),
        icon: const Icon(Icons.add),
        label: const Text('Nuevo movimiento'),
      ),
      body: FutureBuilder<List<Map<String, dynamic>>>(
        future: _future,
        builder: (context, snapshot) {
          if (snapshot.connectionState != ConnectionState.done) return const LoadingView(label: 'Cargando comprobantes…');
          if (snapshot.hasError) return ErrorView(error: snapshot.error!, onRetry: _reload);
          final receipts = snapshot.data!;
          return RefreshIndicator(
            onRefresh: () async => _reload(),
            child: ListView(padding: const EdgeInsets.fromLTRB(16, 12, 16, 96), children: [
              Text('Documentos internos de control, no son facturas fiscales.', style: theme.textTheme.bodySmall),
              const SizedBox(height: 8),
              if (receipts.isEmpty)
                const MessageView(
                  icon: Icons.receipt_long_outlined,
                  title: 'Tus comprobantes aparecerán aquí',
                  message: 'Cada entrada o salida confirmada guarda su documento para consultarlo después.',
                ),
              for (final r in receipts)
                Card(
                  margin: const EdgeInsets.only(bottom: 8),
                  child: ListTile(
                    leading: Icon(r['direction'] == 'IN' ? Icons.south_west : Icons.north_east,
                        color: r['direction'] == 'IN' ? Colors.green.shade700 : theme.colorScheme.error),
                    title: Text(r['folio']?.toString() ?? ''),
                    subtitle: Text('${r['direction'] == 'IN' ? 'Entrada' : 'Salida'} · ${r['reason'] ?? ''}\n${formatDate(r['created_at'])}'),
                    isThreeLine: true,
                    trailing: IconButton(tooltip: 'Abrir PDF', icon: const Icon(Icons.picture_as_pdf_outlined), onPressed: () => openReceiptPdf(context, r)),
                  ),
                ),
            ]),
          );
        },
      ),
    );
  }
}
