import 'package:flutter/material.dart';

import 'premium_ui.dart';

class ErrorState extends StatelessWidget {
  const ErrorState({
    super.key,
    required this.title,
    required this.message,
    this.actionLabel = 'Try again',
    this.onRetry,
  });

  final String title;
  final String message;
  final String actionLabel;
  final VoidCallback? onRetry;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;

    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 420),
        child: PremiumPanel(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              Container(
                width: 64,
                height: 64,
                decoration: BoxDecoration(
                  color: colorScheme.error.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Icon(
                  Icons.error_outline_rounded,
                  size: 32,
                  color: colorScheme.error,
                ),
              ),
              const SizedBox(height: 16),
              Text(
                title,
                style: textTheme.titleLarge,
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 8),
              Text(
                message,
                style: textTheme.bodyMedium?.copyWith(
                  color: colorScheme.onSurfaceVariant,
                ),
                textAlign: TextAlign.center,
              ),
              if (onRetry != null) ...<Widget>[
                const SizedBox(height: 16),
                FilledButton(
                  onPressed: onRetry,
                  style: FilledButton.styleFrom(
                    backgroundColor: colorScheme.error,
                  ),
                  child: Text(actionLabel),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
