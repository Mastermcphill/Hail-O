import 'package:flutter/material.dart';

import '../../theme/app_tokens.dart';
import '../../widgets/premium_ui.dart';

class RideTimelineWidget extends StatelessWidget {
  const RideTimelineWidget({super.key, required this.snapshot});

  final Map<String, dynamic> snapshot;

  @override
  Widget build(BuildContext context) {
    final current = _normalizeState(snapshot);
    final currentIndex = _steps.indexWhere((step) => step.state == current);

    return PremiumPanel(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          const PremiumSectionHeader(
            eyebrow: 'Trip progression',
            title: 'Track the journey step by step.',
            description:
                'Driver assignment, departure readiness, and arrival progression stay readable throughout the trip.',
          ),
          const SizedBox(height: HailoSpacing.lg),
          for (var i = 0; i < _steps.length; i++)
            _TimelineRow(
              key: Key('timeline_step_${_steps[i].state}'),
              step: _steps[i],
              isCurrent: i == currentIndex,
              isComplete: currentIndex >= 0 && i <= currentIndex,
              isLast: i == _steps.length - 1,
            ),
        ],
      ),
    );
  }
}

class _TimelineStep {
  const _TimelineStep({
    required this.state,
    required this.title,
    required this.description,
  });

  final String state;
  final String title;
  final String description;
}

const List<_TimelineStep> _steps = <_TimelineStep>[
  _TimelineStep(
    state: 'REQUESTED',
    title: 'Ride requested',
    description: 'Your trip request is in the network.',
  ),
  _TimelineStep(
    state: 'OFFERED',
    title: 'Driver assigned',
    description: 'Matches are available and an operator is responding.',
  ),
  _TimelineStep(
    state: 'ACCEPTED',
    title: 'Vehicle arriving',
    description: 'The selected ride is being held for you.',
  ),
  _TimelineStep(
    state: 'PAYWALL_PENDING',
    title: 'Booking protected',
    description: 'Escrow protection and seat confirmation are in progress.',
  ),
  _TimelineStep(
    state: 'CONFIRMED',
    title: 'Departure scheduled',
    description: 'Seats are confirmed and your trip is ready.',
  ),
  _TimelineStep(
    state: 'STARTED',
    title: 'Journey started',
    description: 'The vehicle is on route and checkpoints can update.',
  ),
  _TimelineStep(
    state: 'COMPLETED',
    title: 'Arrival',
    description: 'The journey is complete and receipts can be issued.',
  ),
  _TimelineStep(
    state: 'CANCELLED',
    title: 'Cancelled',
    description: 'This trip was cancelled before completion.',
  ),
];

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
  if (_steps.any((step) => step.state == raw)) {
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
  if (raw.contains('COMPLETE') || raw.contains('ARRIV')) {
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
  if (raw.contains('OFFER') || raw.contains('ASSIGN')) {
    return 'OFFERED';
  }
  return 'REQUESTED';
}

class _TimelineRow extends StatelessWidget {
  const _TimelineRow({
    super.key,
    required this.step,
    required this.isCurrent,
    required this.isComplete,
    required this.isLast,
  });

  final _TimelineStep step;
  final bool isCurrent;
  final bool isComplete;
  final bool isLast;

  @override
  Widget build(BuildContext context) {
    final activeColor = Theme.of(context).colorScheme.primary;
    final mutedColor = Theme.of(context).colorScheme.outline;
    final dotColor = isCurrent || isComplete ? activeColor : mutedColor;

    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        SizedBox(
          width: 28,
          child: Column(
            children: <Widget>[
              Container(
                width: 18,
                height: 18,
                decoration: BoxDecoration(
                  color: isComplete
                      ? activeColor
                      : isCurrent
                      ? activeColor.withValues(alpha: 0.14)
                      : Colors.transparent,
                  borderRadius: HailoRadii.pill,
                  border: Border.all(color: dotColor, width: 2),
                ),
                child: isComplete
                    ? const Icon(Icons.check, size: 11, color: Colors.white)
                    : null,
              ),
              if (!isLast)
                Container(
                  width: 2,
                  height: 52,
                  color: isComplete ? activeColor : mutedColor,
                ),
            ],
          ),
        ),
        const SizedBox(width: HailoSpacing.sm),
        Expanded(
          child: Padding(
            padding: const EdgeInsets.only(bottom: HailoSpacing.md),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Text(
                  step.title,
                  style: Theme.of(context).textTheme.titleSmall?.copyWith(
                    fontWeight: isCurrent ? FontWeight.w800 : FontWeight.w700,
                    color: isCurrent ? activeColor : null,
                  ),
                ),
                const SizedBox(height: HailoSpacing.xxs),
                Text(
                  step.description,
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
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
