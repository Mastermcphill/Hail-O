import 'package:flutter/material.dart';

import '../theme/app_tokens.dart';
import 'premium_ui.dart';
import 'trust_badge.dart';

class SeatVisualSpec {
  const SeatVisualSpec({
    required this.seatId,
    required this.label,
    required this.available,
    required this.basePriceMinor,
    required this.markupMinor,
    required this.seatClass,
    required this.tags,
  });

  final String seatId;
  final String label;
  final bool available;
  final int basePriceMinor;
  final int markupMinor;
  final String seatClass;
  final List<String> tags;

  int get totalPriceMinor => basePriceMinor + markupMinor;
}

class SeatLayoutWidget extends StatelessWidget {
  const SeatLayoutWidget({
    super.key,
    required this.seats,
    required this.selectedSeatIds,
    required this.onToggleSeat,
    this.charterMode = false,
  });

  final List<SeatVisualSpec> seats;
  final Set<String> selectedSeatIds;
  final void Function(String seatId) onToggleSeat;
  final bool charterMode;

  @override
  Widget build(BuildContext context) {
    final orderedSeats = <String, SeatVisualSpec>{
      for (final seat in seats) seat.seatId: seat,
    };

    return PremiumPanel(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          const PremiumSectionHeader(
            eyebrow: 'Seat map',
            title: 'Choose the seat that fits your journey.',
            description:
                'Window, front-row, quieter, and executive cues are surfaced directly in the map.',
          ),
          const SizedBox(height: HailoSpacing.lg),
          Row(
            children: <Widget>[
              Expanded(
                child: _SeatTile(
                  spec: orderedSeats['FRONT_RIGHT'] ?? _fallback('FRONT_RIGHT'),
                  selected: selectedSeatIds.contains('FRONT_RIGHT'),
                  onTap: onToggleSeat,
                  charterMode: charterMode,
                ),
              ),
              const SizedBox(width: HailoSpacing.lg),
              const Expanded(child: SizedBox()),
            ],
          ),
          const SizedBox(height: HailoSpacing.lg),
          Row(
            children: <Widget>[
              Expanded(
                child: _SeatTile(
                  spec: orderedSeats['BACK_LEFT'] ?? _fallback('BACK_LEFT'),
                  selected: selectedSeatIds.contains('BACK_LEFT'),
                  onTap: onToggleSeat,
                  charterMode: charterMode,
                ),
              ),
              const SizedBox(width: HailoSpacing.md),
              Expanded(
                child: _SeatTile(
                  spec: orderedSeats['BACK_MIDDLE'] ?? _fallback('BACK_MIDDLE'),
                  selected: selectedSeatIds.contains('BACK_MIDDLE'),
                  onTap: onToggleSeat,
                  charterMode: charterMode,
                ),
              ),
              const SizedBox(width: HailoSpacing.md),
              Expanded(
                child: _SeatTile(
                  spec: orderedSeats['BACK_RIGHT'] ?? _fallback('BACK_RIGHT'),
                  selected: selectedSeatIds.contains('BACK_RIGHT'),
                  onTap: onToggleSeat,
                  charterMode: charterMode,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

SeatVisualSpec _fallback(String seatId) {
  return SeatVisualSpec(
    seatId: seatId,
    label: seatId.replaceAll('_', ' '),
    available: true,
    basePriceMinor: 7000,
    markupMinor: 0,
    seatClass: 'Standard',
    tags: const <String>['Available'],
  );
}

class _SeatTile extends StatelessWidget {
  const _SeatTile({
    required this.spec,
    required this.selected,
    required this.onTap,
    required this.charterMode,
  });

  final SeatVisualSpec spec;
  final bool selected;
  final void Function(String seatId) onTap;
  final bool charterMode;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final backgroundColor = !spec.available
        ? context.hailoTokens.surfaceMuted
        : selected || charterMode
        ? colorScheme.primary.withValues(alpha: 0.10)
        : Colors.white;
    final borderColor = !spec.available
        ? context.hailoTokens.outlineSoft
        : selected || charterMode
        ? colorScheme.primary
        : context.hailoTokens.outlineSoft;

    return InkWell(
      onTap: (spec.available && !charterMode) ? () => onTap(spec.seatId) : null,
      borderRadius: HailoRadii.md,
      child: AnimatedContainer(
        duration: HailoDurations.quick,
        curve: Curves.easeOutCubic,
        padding: const EdgeInsets.all(HailoSpacing.md),
        decoration: BoxDecoration(
          color: backgroundColor,
          borderRadius: HailoRadii.md,
          border: Border.all(color: borderColor),
          boxShadow: <BoxShadow>[
            BoxShadow(
              blurRadius: 18,
              offset: const Offset(0, 12),
              color: selected || charterMode
                  ? colorScheme.primary.withValues(alpha: 0.12)
                  : Colors.black.withValues(alpha: 0.04),
            ),
          ],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Row(
              children: <Widget>[
                Icon(
                  Icons.airline_seat_recline_normal_rounded,
                  color: selected || charterMode
                      ? colorScheme.primary
                      : colorScheme.onSurface,
                ),
                const Spacer(),
                if (!spec.available)
                  const PremiumPill(label: 'Taken')
                else if (charterMode)
                  const PremiumPill(label: 'Included')
                else if (selected)
                  const PremiumPill(label: 'Selected'),
              ],
            ),
            const SizedBox(height: HailoSpacing.md),
            Text(
              spec.label,
              style: Theme.of(
                context,
              ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w800),
            ),
            const SizedBox(height: HailoSpacing.xxs),
            Text(
              spec.seatClass,
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                color: colorScheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: HailoSpacing.sm),
            Wrap(
              spacing: HailoSpacing.xs,
              runSpacing: HailoSpacing.xs,
              children: <Widget>[
                for (final tag in spec.tags)
                  TrustBadge(
                    label: tag,
                    icon: Icons.label_outline_rounded,
                    tint: selected || charterMode ? colorScheme.primary : null,
                  ),
              ],
            ),
            const SizedBox(height: HailoSpacing.sm),
            Text(
              _money(spec.totalPriceMinor),
              style: Theme.of(context).textTheme.titleSmall?.copyWith(
                color: colorScheme.primary,
                fontWeight: FontWeight.w800,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

String _money(int amountMinor) {
  return '\$${(amountMinor / 100).toStringAsFixed(2)}';
}
