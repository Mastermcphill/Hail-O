import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../session/auth_session.dart';

class BootScreen extends StatelessWidget {
  const BootScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final session = context.watch<AuthSession>();
    final startupMessage =
        session.startupFailureMessage ?? session.startupStage;

    return Scaffold(
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              SizedBox(
                height: 56,
                child: Image.asset(
                  'assets/brand/logo_lockup.png',
                  fit: BoxFit.contain,
                  errorBuilder: (context, error, stackTrace) => Icon(
                    Icons.local_taxi,
                    size: 40,
                    color: colorScheme.primary,
                  ),
                ),
              ),
              const SizedBox(height: 16),
              const CircularProgressIndicator(),
              const SizedBox(height: 12),
              Text(startupMessage),
              if (session.startupFailureMessage != null) ...<Widget>[
                const SizedBox(height: 8),
                Text(
                  'Continuing in safe mode...',
                  style: TextStyle(color: colorScheme.onSurfaceVariant),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
