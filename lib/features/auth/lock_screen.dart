import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/session.dart';

/// Pantalla de bloqueo con biometría: pide la huella al abrirse.
class LockScreen extends StatefulWidget {
  const LockScreen({super.key});

  @override
  State<LockScreen> createState() => _LockScreenState();
}

class _LockScreenState extends State<LockScreen> {
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _unlock());
  }

  Future<void> _unlock() async {
    if (_busy) return;
    setState(() => _busy = true);
    await context.read<SessionController>().unlock();
    if (mounted) setState(() => _busy = false);
  }

  @override
  Widget build(BuildContext context) {
    final session = context.watch<SessionController>();
    final theme = Theme.of(context);
    return Scaffold(
      body: SafeArea(
        child: Center(
          child: Padding(
            padding: const EdgeInsets.all(32),
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              Image.asset('assets/images/mi-inventario.logo.png', height: 120),
              const SizedBox(height: 16),
              Text('Hola${session.profile?.firstName.isNotEmpty == true ? ', ${session.profile!.firstName}' : ''}',
                  style: theme.textTheme.headlineSmall),
              const SizedBox(height: 8),
              Text('Usa tu huella o rostro para continuar.', style: theme.textTheme.bodyMedium, textAlign: TextAlign.center),
              const SizedBox(height: 28),
              FilledButton.icon(
                onPressed: _busy ? null : _unlock,
                icon: const Icon(Icons.fingerprint),
                label: const Text('Desbloquear'),
              ),
              const SizedBox(height: 12),
              TextButton(onPressed: _busy ? null : session.logout, child: const Text('Entrar con otra cuenta')),
            ]),
          ),
        ),
      ),
    );
  }
}
