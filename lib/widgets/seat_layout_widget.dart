import 'package:flutter/material.dart';

class SeatLayoutWidget extends StatelessWidget {
  const SeatLayoutWidget({
    super.key,
    required this.availableSeatIds,
    required this.selectedSeatIds,
    required this.onToggleSeat,
  });

  final List<String> availableSeatIds;
  final Set<String> selectedSeatIds;
  final void Function(String seatId) onToggleSeat;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            Text('Seat Layout', style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 16),
            Row(
              children: <Widget>[
                Expanded(
                  child: _SeatTile(
                    seatId: 'FRONT_RIGHT',
                    available: availableSeatIds.contains('FRONT_RIGHT'),
                    selected: selectedSeatIds.contains('FRONT_RIGHT'),
                    onTap: onToggleSeat,
                  ),
                ),
                const SizedBox(width: 12),
                const Expanded(child: SizedBox()),
              ],
            ),
            const SizedBox(height: 16),
            Row(
              children: <Widget>[
                Expanded(
                  child: _SeatTile(
                    seatId: 'BACK_LEFT',
                    available: availableSeatIds.contains('BACK_LEFT'),
                    selected: selectedSeatIds.contains('BACK_LEFT'),
                    onTap: onToggleSeat,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: _SeatTile(
                    seatId: 'BACK_MIDDLE',
                    available: availableSeatIds.contains('BACK_MIDDLE'),
                    selected: selectedSeatIds.contains('BACK_MIDDLE'),
                    onTap: onToggleSeat,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: _SeatTile(
                    seatId: 'BACK_RIGHT',
                    available: availableSeatIds.contains('BACK_RIGHT'),
                    selected: selectedSeatIds.contains('BACK_RIGHT'),
                    onTap: onToggleSeat,
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _SeatTile extends StatelessWidget {
  const _SeatTile({
    required this.seatId,
    required this.available,
    required this.selected,
    required this.onTap,
  });

  final String seatId;
  final bool available;
  final bool selected;
  final void Function(String seatId) onTap;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final backgroundColor = !available
        ? colorScheme.surfaceContainerHighest
        : selected
        ? colorScheme.primaryContainer
        : colorScheme.surface;
    final borderColor = !available
        ? colorScheme.outlineVariant
        : selected
        ? colorScheme.primary
        : colorScheme.outline;

    return InkWell(
      onTap: available ? () => onTap(seatId) : null,
      borderRadius: BorderRadius.circular(8),
      child: Ink(
        padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 10),
        decoration: BoxDecoration(
          color: backgroundColor,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: borderColor),
        ),
        child: Column(
          children: <Widget>[
            const Icon(Icons.event_seat),
            const SizedBox(height: 6),
            Text(
              seatId,
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ],
        ),
      ),
    );
  }
}
