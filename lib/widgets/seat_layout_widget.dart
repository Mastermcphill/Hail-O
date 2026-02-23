import 'package:flutter/material.dart';

class SeatLayoutWidget extends StatelessWidget {
  const SeatLayoutWidget({
    super.key,
    required this.seats,
    required this.selectedSeatIds,
    required this.onToggleSeat,
    this.readOnly = false,
  });

  final List<Map<String, dynamic>> seats;
  final Set<String> selectedSeatIds;
  final ValueChanged<String> onToggleSeat;
  final bool readOnly;

  @override
  Widget build(BuildContext context) {
    final byId = <String, Map<String, dynamic>>{
      for (final seat in seats) _seatId(seat): seat,
    };
    final ordered = <String>{
      'FRONT_RIGHT',
      'BACK_LEFT',
      'BACK_MIDDLE',
      'BACK_RIGHT',
      ...byId.keys.where(
        (id) =>
            id != 'FRONT_RIGHT' &&
            id != 'BACK_LEFT' &&
            id != 'BACK_MIDDLE' &&
            id != 'BACK_RIGHT',
      ),
    }.toList();

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Text('Seat Layout', style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 12),
            for (final seatId in ordered)
              Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: _SeatTile(
                  seat: byId[seatId] ?? <String, dynamic>{'seat_id': seatId},
                  selected: selectedSeatIds.contains(seatId),
                  onTap: (readOnly || !_isAvailable(byId[seatId]))
                      ? null
                      : () => onToggleSeat(seatId),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _SeatTile extends StatelessWidget {
  const _SeatTile({required this.seat, required this.selected, this.onTap});

  final Map<String, dynamic> seat;
  final bool selected;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final seatId = _seatId(seat);
    final available = _isAvailable(seat);
    return Material(
      color: selected
          ? Theme.of(context).colorScheme.primaryContainer
          : Theme.of(context).colorScheme.surfaceContainerHighest,
      borderRadius: BorderRadius.circular(10),
      child: ListTile(
        title: Text(seatId),
        subtitle: Text(available ? 'Available' : 'Unavailable'),
        trailing: Icon(
          selected ? Icons.check_circle : Icons.event_seat_outlined,
          color: selected ? Theme.of(context).colorScheme.primary : null,
        ),
        onTap: onTap,
      ),
    );
  }
}

String _seatId(Map<String, dynamic>? seat) {
  final id = seat?['seat_id'] ?? seat?['id'];
  if (id is String && id.trim().isNotEmpty) {
    return id.trim();
  }
  return 'UNKNOWN_SEAT';
}

bool _isAvailable(Map<String, dynamic>? seat) {
  if (seat == null) {
    return false;
  }
  final available = seat['is_available'];
  if (available is bool) {
    return available;
  }
  return true;
}
