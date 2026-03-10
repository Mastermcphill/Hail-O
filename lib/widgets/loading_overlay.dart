import 'package:flutter/material.dart';

import '../theme/app_tokens.dart';
import 'premium_ui.dart';

class LoadingOverlay extends StatelessWidget {
  const LoadingOverlay({
    super.key,
    required this.isLoading,
    required this.child,
    this.message = 'Please wait...',
  });

  final bool isLoading;
  final String message;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    if (!isLoading) {
      return child;
    }

    return Stack(
      children: <Widget>[
        child,
        Positioned.fill(
          child: ColoredBox(
            color: const Color(0xFF061A2E).withValues(alpha: 0.16),
            child: Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 320),
                child: PremiumPanel(
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: <Widget>[
                      const SizedBox(
                        width: 22,
                        height: 22,
                        child: CircularProgressIndicator(strokeWidth: 2.2),
                      ),
                      const SizedBox(width: HailoSpacing.md),
                      Expanded(
                        child: Text(
                          message,
                          style: Theme.of(context).textTheme.bodyMedium,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }
}
