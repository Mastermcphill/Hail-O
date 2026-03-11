import 'package:flutter/material.dart';

import '../theme/app_tokens.dart';
import 'premium_ui.dart';

class RideTypeCard extends StatelessWidget {
  const RideTypeCard({
    super.key,
    required this.title,
    required this.description,
    required this.icon,
    required this.selected,
    required this.onTap,
  });

  final String title;
  final String description;
  final IconData icon;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return InkWell(
      borderRadius: HailoRadii.md,
      onTap: onTap,
      child: PremiumPanel(
        padding: const EdgeInsets.all(HailoSpacing.md),
        borderRadius: HailoRadii.md,
        borderColor: selected
            ? colorScheme.primary.withValues(alpha: 0.32)
            : context.hailoTokens.outlineSoft,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Container(
              width: 44,
              height: 44,
              decoration: BoxDecoration(
                color: selected
                    ? colorScheme.primary.withValues(alpha: 0.12)
                    : context.hailoTokens.surfaceMuted,
                borderRadius: HailoRadii.sm,
              ),
              child: Icon(
                icon,
                color: selected ? colorScheme.primary : colorScheme.onSurface,
              ),
            ),
            const SizedBox(height: HailoSpacing.md),
            Text(
              title,
              style: Theme.of(context).textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.w700,
                color: selected ? colorScheme.primary : null,
              ),
            ),
            const SizedBox(height: HailoSpacing.xs),
            Text(
              description,
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                color: colorScheme.onSurfaceVariant,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
