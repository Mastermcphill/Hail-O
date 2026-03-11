import 'package:flutter/material.dart';

import '../theme/app_tokens.dart';

class SeatClassChip extends StatelessWidget {
  const SeatClassChip({
    super.key,
    required this.label,
    required this.description,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final String description;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return InkWell(
      borderRadius: HailoRadii.md,
      onTap: onTap,
      child: AnimatedContainer(
        duration: HailoDurations.quick,
        curve: Curves.easeOutCubic,
        padding: const EdgeInsets.all(HailoSpacing.md),
        decoration: BoxDecoration(
          color: selected
              ? colorScheme.primary.withValues(alpha: 0.10)
              : Colors.white.withValues(alpha: 0.90),
          borderRadius: HailoRadii.md,
          border: Border.all(
            color: selected
                ? colorScheme.primary.withValues(alpha: 0.36)
                : context.hailoTokens.outlineSoft,
          ),
          boxShadow: selected
              ? <BoxShadow>[
                  BoxShadow(
                    blurRadius: 22,
                    offset: const Offset(0, 12),
                    color: colorScheme.primary.withValues(alpha: 0.12),
                  ),
                ]
              : const <BoxShadow>[],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Text(
              label,
              style: Theme.of(context).textTheme.titleSmall?.copyWith(
                fontWeight: FontWeight.w700,
                color: selected ? colorScheme.primary : null,
              ),
            ),
            const SizedBox(height: HailoSpacing.xxs),
            Text(
              description,
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
