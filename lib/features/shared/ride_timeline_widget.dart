import 'package:flutter/material.dart';

class RideTimelineWidget extends StatelessWidget {
  const RideTimelineWidget({super.key, required this.snapshot});

  final Map<String, dynamic> snapshot;

  @override
  Widget build(BuildContext context) {
    final states = _states;
    final currentState = _resolveState(snapshot);
    final currentIndex = states.indexOf(currentState);

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Text(
              'Ride Timeline',
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: 10),
            for (var i = 0; i < states.length; i++)
              _TimelineStep(
                label: states[i],
                isActive: i == currentIndex,
                isReached: currentIndex >= 0 && i <= currentIndex,
                isLast: i == states.length - 1,
              ),
          ],
        ),
      ),
    );
  }
}

class _TimelineStep extends StatelessWidget {
  const _TimelineStep({
    required this.label,
    required this.isActive,
    required this.isReached,
    required this.isLast,
  });

  final String label;
  final bool isActive;
  final bool isReached;
  final bool isLast;

  @override
  Widget build(BuildContext context) {
    final color = isActive
        ? Theme.of(context).colorScheme.primary
        : (isReached
              ? Theme.of(context).colorScheme.secondary
              : Theme.of(context).colorScheme.outlineVariant);

    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        SizedBox(
          width: 20,
          child: Column(
            children: <Widget>[
              Icon(
                isReached ? Icons.check_circle : Icons.radio_button_unchecked,
                size: 16,
                color: color,
              ),
              if (!isLast)
                Container(
                  width: 2,
                  height: 24,
                  color: color.withValues(alpha: 0.5),
                ),
            ],
          ),
        ),
        const SizedBox(width: 8),
        Padding(
          padding: const EdgeInsets.only(top: 1),
          child: Text(
            label,
            style: TextStyle(
              fontWeight: isActive ? FontWeight.w700 : FontWeight.w400,
            ),
          ),
        ),
      ],
    );
  }
}

const List<String> _states = <String>[
  'REQUESTED',
  'OFFERED',
  'ACCEPTED',
  'PAYWALL_PENDING',
  'CONFIRMED',
  'STARTED',
  'COMPLETED',
  'CANCELLED',
];

String _resolveState(Map<String, dynamic> snapshot) {
  final ride = _asMap(snapshot['ride']);
  final raw = _firstString(<Object?>[
    snapshot['ride_status'],
    snapshot['status'],
    snapshot['state'],
    ride['ride_status'],
    ride['status'],
    ride['state'],
  ]).toUpperCase();

  if (raw.contains('CANCEL')) {
    return 'CANCELLED';
  }
  if (raw.contains('COMPLETE')) {
    return 'COMPLETED';
  }
  if (raw.contains('START')) {
    return 'STARTED';
  }
  if (raw.contains('CONFIRM')) {
    return 'CONFIRMED';
  }
  if (raw.contains('PAYWALL')) {
    return 'PAYWALL_PENDING';
  }
  if (raw.contains('ACCEPT')) {
    return 'ACCEPTED';
  }
  if (raw.contains('OFFER')) {
    return 'OFFERED';
  }
  return 'REQUESTED';
}

Map<String, dynamic> _asMap(dynamic value) {
  if (value is Map<String, dynamic>) {
    return value;
  }
  if (value is Map) {
    return value.map(
      (key, mapValue) => MapEntry<String, dynamic>(key.toString(), mapValue),
    );
  }
  return <String, dynamic>{};
}

String _firstString(List<Object?> values) {
  for (final value in values) {
    if (value is String && value.trim().isNotEmpty) {
      return value.trim();
    }
  }
  return '';
}
