import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../theme/app_tokens.dart';
import '../../../widgets/premium_ui.dart';
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
      backgroundColor: Colors.transparent,
      body: BrandBackdrop(
        child: Center(
          child: Padding(
            padding: const EdgeInsets.all(HailoSpacing.lg),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 520),
              child: PremiumPanel(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: <Widget>[
                    SizedBox(
                      height: 56,
                      child: Image.asset(
                        'assets/brand/logo_lockup.png',
                        fit: BoxFit.contain,
                        errorBuilder: (context, error, stackTrace) => Icon(
                          Icons.local_taxi_rounded,
                          size: 40,
                          color: colorScheme.primary,
                        ),
                      ),
                    ),
                    const SizedBox(height: HailoSpacing.lg),
                    const SizedBox(
                      width: 30,
                      height: 30,
                      child: CircularProgressIndicator(strokeWidth: 2.4),
                    ),
                    const SizedBox(height: HailoSpacing.md),
                    Text(
                      'Preparing your HAIL-O experience',
                      style: Theme.of(context).textTheme.titleLarge,
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: HailoSpacing.sm),
                    Text(
                      startupMessage,
                      textAlign: TextAlign.center,
                      style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                        color: colorScheme.onSurfaceVariant,
                      ),
                    ),
                    if (session.startupFailureMessage != null) ...<Widget>[
                      const SizedBox(height: HailoSpacing.md),
                      PremiumPill(
                        label: 'Continuing in safe mode',
                        icon: Icons.info_outline_rounded,
                        backgroundColor: colorScheme.error.withValues(
                          alpha: 0.10,
                        ),
                        foregroundColor: colorScheme.error,
                      ),
                    ],
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
