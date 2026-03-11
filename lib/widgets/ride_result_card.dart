import 'package:flutter/material.dart';

import '../theme/app_tokens.dart';
import 'premium_ui.dart';
import 'trust_badge.dart';

class RideResultCard extends StatelessWidget {
  const RideResultCard({
    super.key,
    required this.category,
    required this.operatorName,
    required this.scheduleLabel,
    required this.priceLabel,
    required this.ratingLabel,
    required this.seatAvailabilityLabel,
    required this.primaryLabel,
    required this.onPrimaryPressed,
    this.secondaryLabel,
    this.onSecondaryPressed,
    this.tags = const <String>[],
    this.trustBadges = const <TrustBadge>[],
    this.heroNote,
  });

  final String category;
  final String operatorName;
  final String scheduleLabel;
  final String priceLabel;
  final String ratingLabel;
  final String seatAvailabilityLabel;
  final String primaryLabel;
  final VoidCallback onPrimaryPressed;
  final String? secondaryLabel;
  final VoidCallback? onSecondaryPressed;
  final List<String> tags;
  final List<TrustBadge> trustBadges;
  final String? heroNote;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return PremiumPanel(
      padding: const EdgeInsets.all(HailoSpacing.md),
      borderRadius: HailoRadii.md,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          if (tags.isNotEmpty)
            Wrap(
              spacing: HailoSpacing.xs,
              runSpacing: HailoSpacing.xs,
              children: <Widget>[
                for (final tag in tags)
                  PremiumPill(label: tag, icon: Icons.tune_rounded),
              ],
            ),
          if (tags.isNotEmpty) const SizedBox(height: HailoSpacing.md),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Text(
                      category,
                      style: theme.textTheme.titleLarge?.copyWith(
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    const SizedBox(height: HailoSpacing.xxs),
                    Text(
                      operatorName,
                      style: theme.textTheme.bodyMedium?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
              ),
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: <Widget>[
                  Text(
                    priceLabel,
                    style: theme.textTheme.titleLarge?.copyWith(
                      color: theme.colorScheme.primary,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  Text(
                    seatAvailabilityLabel,
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
            ],
          ),
          const SizedBox(height: HailoSpacing.md),
          Row(
            children: <Widget>[
              Expanded(
                child: _ResultMeta(label: 'Departure', value: scheduleLabel),
              ),
              Expanded(
                child: _ResultMeta(label: 'Rating', value: ratingLabel),
              ),
            ],
          ),
          if (heroNote != null) ...<Widget>[
            const SizedBox(height: HailoSpacing.sm),
            Text(
              heroNote!,
              style: theme.textTheme.bodyMedium?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ],
          if (trustBadges.isNotEmpty) ...<Widget>[
            const SizedBox(height: HailoSpacing.md),
            Wrap(
              spacing: HailoSpacing.xs,
              runSpacing: HailoSpacing.xs,
              children: trustBadges,
            ),
          ],
          const SizedBox(height: HailoSpacing.lg),
          Row(
            children: <Widget>[
              Expanded(
                child: FilledButton(
                  onPressed: onPrimaryPressed,
                  child: Text(primaryLabel),
                ),
              ),
              if (secondaryLabel != null &&
                  onSecondaryPressed != null) ...<Widget>[
                const SizedBox(width: HailoSpacing.sm),
                Expanded(
                  child: OutlinedButton(
                    onPressed: onSecondaryPressed,
                    child: Text(secondaryLabel!),
                  ),
                ),
              ],
            ],
          ),
        ],
      ),
    );
  }
}

class _ResultMeta extends StatelessWidget {
  const _ResultMeta({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Text(
          label,
          style: Theme.of(context).textTheme.labelMedium?.copyWith(
            color: Theme.of(context).colorScheme.onSurfaceVariant,
          ),
        ),
        const SizedBox(height: HailoSpacing.xxs),
        Text(
          value,
          style: Theme.of(
            context,
          ).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w700),
        ),
      ],
    );
  }
}
