import 'package:flutter/material.dart';

class RideTimelineWidget extends StatelessWidget {
  const RideTimelineWidget({super.key, required this.snapshot});

  final Map<String, dynamic> snapshot;

  static const List<String> _states = <String>[
    'REQUESTED',
    'OFFERED',
    'ACCEPTED',
    'PAYWALL_PENDING',
    'CONFIRMED',
    'STARTED',
    'COMPLETED',
    'CANCELLED',
  ];

  @override
  Widget build(BuildContext context) {
    final current = _normalizeState(snapshot);
    final currentIndex = _stateIndex(current);

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Text(
              'Ride Timeline',
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: 12),
            for (var i = 0; i < _states.length; i++)
              _TimelineRow(
                key: Key('timeline_step_${_states[i]}'),
                state: _states[i],
                isCurrent: i == currentIndex,
                isComplete: currentIndex >= 0 && i <= currentIndex,
                isLast: i == _states.length - 1,
              ),
          ],
        ),
      ),
    );
  }

  String _normalizeState(Map<String, dynamic> snapshot) {
    final ride = _asMap(snapshot['ride']);
    final raw =
        (snapshot['status'] ??
                snapshot['state'] ??
                snapshot['ride_status'] ??
                ride['status'] ??
                ride['state'] ??
                ride['ride_status'])
            ?.toString()
            .trim()
            .toUpperCase();

    if (raw == null || raw.isEmpty) {
      return 'REQUESTED';
    }

    if (_states.contains(raw)) {
      return raw;
    }

    if (raw.contains('BOOK')) {
      return 'REQUESTED';
    }
    if (raw.contains('ACCEPT')) {
      return 'ACCEPTED';
    }
    if (raw.contains('START')) {
      return 'STARTED';
    }
    if (raw.contains('COMPLETE')) {
      return 'COMPLETED';
    }
    if (raw.contains('CANCEL')) {
      return 'CANCELLED';
    }
    if (raw.contains('PAY')) {
      return 'PAYWALL_PENDING';
    }
    if (raw.contains('CONFIRM')) {
      return 'CONFIRMED';
    }
    if (raw.contains('OFFER')) {
      return 'OFFERED';
    }
    return 'REQUESTED';
  }

  int _stateIndex(String state) {
    return _states.indexOf(state);
  }

  Map<String, dynamic> _asMap(dynamic value) {
    if (value is Map<String, dynamic>) {
      return value;
    }
    if (value is Map) {
      return value.map(
        (key, item) => MapEntry<String, dynamic>(key.toString(), item),
      );
    }
    return <String, dynamic>{};
  }
}

class _TimelineRow extends StatelessWidget {
  const _TimelineRow({
    super.key,
    required this.state,
    required this.isCurrent,
    required this.isComplete,
    required this.isLast,
  });

  final String state;
  final bool isCurrent;
  final bool isComplete;
  final bool isLast;

  @override
  Widget build(BuildContext context) {
    final activeColor = Theme.of(context).colorScheme.primary;
    final mutedColor = Theme.of(context).colorScheme.outline;
    final color = isCurrent || isComplete ? activeColor : mutedColor;

    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        SizedBox(
          width: 22,
          child: Column(
            children: <Widget>[
              Icon(
                isComplete ? Icons.check_circle : Icons.radio_button_unchecked,
                color: color,
                size: 18,
              ),
              if (!isLast)
                Container(
                  width: 2,
                  height: 24,
                  color: isComplete ? activeColor : mutedColor,
                ),
            ],
          ),
        ),
        const SizedBox(width: 8),
        Padding(
          padding: const EdgeInsets.only(top: 1),
          child: Text(
            state,
            style: TextStyle(
              fontWeight: isCurrent ? FontWeight.w700 : FontWeight.w400,
              color: color,
            ),
          ),
        ),
      ],
    );
  }
}
