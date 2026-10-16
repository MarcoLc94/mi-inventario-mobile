import 'package:flutter/material.dart';

class SplashScreen extends StatelessWidget {
  const SplashScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      body: Center(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Image.asset('assets/images/mi-inventario.logo.png', width: 240),
          const SizedBox(height: 8),
          Text('Todo en orden. Todo bajo control.', style: theme.textTheme.bodyMedium),
          const SizedBox(height: 28),
          const SizedBox(width: 160, child: LinearProgressIndicator()),
        ]),
      ),
    );
  }
}
