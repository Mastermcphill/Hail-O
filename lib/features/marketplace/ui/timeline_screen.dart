import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import '../models/timeline_event.dart';
import '../state/marketplace_controller.dart';

class MarketplaceTimelineScreen extends StatefulWidget {
  const MarketplaceTimelineScreen({super.key, required this.purchaseId});

  final String purchaseId;

  @override
  State<MarketplaceTimelineScreen> createState() =>
      _MarketplaceTimelineScreenState();
}

class _MarketplaceTimelineScreenState extends State<MarketplaceTimelineScreen> {
  static final DateFormat _timeFormat = DateFormat('MMM d, HH:mm');

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) {
        return;
      }
      context.read<MarketplaceController>().loadTimeline(widget.purchaseId);
    });
  }

  @override
  Widget build(BuildContext context) {
    return Consumer<MarketplaceController>(
      builder: (context, controller, child) {
        final events = controller.timelineEvents;

        if (controller.loadingTimeline && events.isEmpty) {
          return const Center(child: CircularProgressIndicator());
        }

        if (controller.errorMessage != null && events.isEmpty) {
          return _TimelineErrorState(
            message: controller.errorMessage!,
            onRetry: () => controller.loadTimeline(widget.purchaseId),
          );
        }

        return RefreshIndicator(
          onRefresh: () => controller.loadTimeline(widget.purchaseId),
          child: ListView(
            key: const Key('marketplace_timeline_list'),
            padding: const EdgeInsets.all(16),
            children: <Widget>[
              Text(
                'Marketplace Timeline',
                style: Theme.of(context).textTheme.headlineSmall,
              ),
              const SizedBox(height: 6),
              SelectableText('purchase_id: ${widget.purchaseId}'),
              const SizedBox(height: 12),
              if (events.isEmpty)
                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(12),
                    child: Text(
                      'No events yet. Pull down to refresh.',
                      style: Theme.of(context).textTheme.bodyMedium,
                    ),
                  ),
                )
              else
                ...events.asMap().entries.map((entry) {
                  final index = entry.key;
                  final event = entry.value;
                  final isLast = index == events.length - 1;
                  return _TimelineEventTile(
                    key: Key('marketplace_timeline_event_$index'),
                    event: event,
                    formattedTime: _timeFormat.format(
                      event.occurredAt.toLocal(),
                    ),
                    isLast: isLast,
                  );
                }),
              if (controller.errorMessage != null) ...<Widget>[
                const SizedBox(height: 8),
                Text(
                  controller.errorMessage!,
                  style: TextStyle(color: Theme.of(context).colorScheme.error),
                ),
              ],
              const SizedBox(height: 24),
            ],
          ),
        );
      },
    );
  }
}

class _TimelineEventTile extends StatelessWidget {
  const _TimelineEventTile({
    super.key,
    required this.event,
    required this.formattedTime,
    required this.isLast,
  });

  final TimelineEvent event;
  final String formattedTime;
  final bool isLast;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final statusColor = _statusColor(event.status, colorScheme);
    final statusIcon = _statusIcon(event.status);

    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        SizedBox(
          width: 28,
          child: Column(
            children: <Widget>[
              Icon(statusIcon, size: 16, color: statusColor),
              if (!isLast)
                Container(
                  width: 2,
                  height: 56,
                  color: statusColor.withValues(alpha: 0.35),
                ),
            ],
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: Card(
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Row(
                    children: <Widget>[
                      Expanded(
                        child: Text(
                          event.title,
                          style: Theme.of(context).textTheme.titleSmall,
                        ),
                      ),
                      _StatusChip(status: event.status),
                    ],
                  ),
                  const SizedBox(height: 4),
                  Text(
                    event.description,
                    style: Theme.of(context).textTheme.bodyMedium,
                  ),
                  const SizedBox(height: 6),
                  Text(
                    formattedTime,
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                ],
              ),
            ),
          ),
        ),
      ],
    );
  }
}

class _StatusChip extends StatelessWidget {
  const _StatusChip({required this.status});

  final TimelineEventStatus status;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final background = _statusColor(
      status,
      colorScheme,
    ).withValues(alpha: 0.12);
    return Chip(
      label: Text(status.name.toUpperCase()),
      visualDensity: VisualDensity.compact,
      backgroundColor: background,
      side: BorderSide(color: _statusColor(status, colorScheme)),
      labelStyle: TextStyle(
        color: _statusColor(status, colorScheme),
        fontWeight: FontWeight.w600,
      ),
    );
  }
}

class _TimelineErrorState extends StatelessWidget {
  const _TimelineErrorState({required this.message, required this.onRetry});

  final String message;
  final Future<void> Function() onRetry;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 420),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: <Widget>[
              Text(
                'Could not load timeline',
                style: Theme.of(context).textTheme.titleMedium,
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 8),
              Text(
                message,
                style: TextStyle(color: Theme.of(context).colorScheme.error),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 12),
              FilledButton(onPressed: onRetry, child: const Text('Retry')),
            ],
          ),
        ),
      ),
    );
  }
}

Color _statusColor(TimelineEventStatus status, ColorScheme colorScheme) {
  switch (status) {
    case TimelineEventStatus.success:
      return colorScheme.primary;
    case TimelineEventStatus.warning:
      return colorScheme.tertiary;
    case TimelineEventStatus.failed:
      return colorScheme.error;
    case TimelineEventStatus.pending:
      return colorScheme.secondary;
  }
}

IconData _statusIcon(TimelineEventStatus status) {
  switch (status) {
    case TimelineEventStatus.success:
      return Icons.check_circle;
    case TimelineEventStatus.warning:
      return Icons.warning_amber;
    case TimelineEventStatus.failed:
      return Icons.error;
    case TimelineEventStatus.pending:
      return Icons.timelapse;
  }
}
