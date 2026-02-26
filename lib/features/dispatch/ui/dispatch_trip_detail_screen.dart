import 'package:flutter/material.dart';

import '../../../core/api/api_errors.dart';
import '../data/dispatch_repository.dart';
import '../models/dispatch_models.dart';

class DispatchTripDetailScreen extends StatefulWidget {
  const DispatchTripDetailScreen({
    super.key,
    required this.repository,
    required this.tripId,
  });

  final DispatchRepository repository;
  final String tripId;

  @override
  State<DispatchTripDetailScreen> createState() =>
      _DispatchTripDetailScreenState();
}

class _DispatchTripDetailScreenState extends State<DispatchTripDetailScreen> {
  static const Map<String, List<String>> _statusTransitions =
      <String, List<String>>{
        'created': <String>['searching', 'canceled'],
        'searching': <String>['assigned', 'canceled'],
        'assigned': <String>['enroute_pickup', 'canceled'],
        'enroute_pickup': <String>['picked_up', 'canceled'],
        'picked_up': <String>['enroute_dropoff', 'canceled'],
        'enroute_dropoff': <String>['delivered', 'canceled'],
        'delivered': <String>[],
        'canceled': <String>[],
      };

  final TextEditingController _driverIdController = TextEditingController();
  DispatchTrip? _trip;
  DispatchAssignment? _assignment;
  final List<DispatchStatusEvent> _history = <DispatchStatusEvent>[];
  bool _loading = true;
  bool _busy = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _loadTrip();
  }

  @override
  void dispose() {
    _driverIdController.dispose();
    super.dispose();
  }

  Future<void> _loadTrip({bool showSpinner = true}) async {
    if (showSpinner) {
      setState(() {
        _loading = true;
        _error = null;
      });
    } else {
      setState(() {
        _error = null;
      });
    }
    try {
      final trip = await widget.repository.getTrip(widget.tripId);
      if (!mounted) {
        return;
      }
      setState(() {
        _trip = trip;
      });
      _syncHistoryWithTrip(trip);
    } catch (error) {
      if (!mounted) {
        return;
      }
      setState(() {
        _error = formatApiError(error);
      });
    } finally {
      if (mounted) {
        setState(() {
          _loading = false;
        });
      }
    }
  }

  Future<void> _transitionTo(String nextStatus) async {
    final trip = _trip;
    if (trip == null) {
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final result = await widget.repository.updateStatus(
        tripId: trip.id,
        status: nextStatus,
      );
      if (!mounted) {
        return;
      }
      setState(() {
        _trip = result.trip;
      });
      _appendHistoryEvent(result.event);
    } catch (error) {
      if (!mounted) {
        return;
      }
      setState(() {
        _error = formatApiError(error);
      });
    } finally {
      if (mounted) {
        setState(() {
          _busy = false;
        });
      }
    }
  }

  Future<void> _assignDriver() async {
    final trip = _trip;
    if (trip == null) {
      return;
    }
    final driverId = _driverIdController.text.trim();
    if (driverId.isEmpty) {
      setState(() {
        _error = 'Enter a driver id before assigning.';
      });
      return;
    }
    final fromStatus = trip.status;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final result = await widget.repository.assignDriver(
        tripId: trip.id,
        driverId: driverId,
      );
      if (!mounted) {
        return;
      }
      setState(() {
        _trip = result.trip;
        _assignment = result.assignment;
      });
      _appendAssignmentHistory(
        fromStatus: fromStatus,
        assignedTrip: result.trip,
        assignment: result.assignment,
      );
    } catch (error) {
      if (!mounted) {
        return;
      }
      setState(() {
        _error = formatApiError(error);
      });
    } finally {
      if (mounted) {
        setState(() {
          _busy = false;
        });
      }
    }
  }

  void _syncHistoryWithTrip(DispatchTrip trip) {
    if (_history.isEmpty) {
      _appendHistoryEvent(
        DispatchStatusEvent(
          fromStatus: null,
          toStatus: trip.status,
          actorUserId: trip.userId,
          createdAt: trip.createdAt ?? trip.updatedAt,
          metadata: const <String, dynamic>{'source': 'trip_snapshot'},
        ),
      );
      return;
    }
    final last = _history.isEmpty ? null : _history.last;
    if (last != null && last.toStatus != trip.status) {
      _appendHistoryEvent(
        DispatchStatusEvent(
          fromStatus: last.toStatus,
          toStatus: trip.status,
          actorUserId: trip.userId,
          createdAt: trip.updatedAt,
          metadata: const <String, dynamic>{'source': 'trip_refresh'},
        ),
      );
    }
  }

  void _appendAssignmentHistory({
    required String fromStatus,
    required DispatchTrip assignedTrip,
    required DispatchAssignment assignment,
  }) {
    final createdAt = assignment.createdAt ?? assignedTrip.updatedAt;
    if (fromStatus == 'created') {
      _appendHistoryEvent(
        DispatchStatusEvent(
          fromStatus: 'created',
          toStatus: 'searching',
          createdAt: createdAt,
          metadata: const <String, dynamic>{'source': 'assign_call'},
        ),
      );
      _appendHistoryEvent(
        DispatchStatusEvent(
          fromStatus: 'searching',
          toStatus: assignedTrip.status,
          createdAt: createdAt,
          metadata: <String, dynamic>{
            'source': 'assign_call',
            'assignment_id': assignment.id,
            'driver_id': assignment.driverId,
          },
        ),
      );
      return;
    }
    _appendHistoryEvent(
      DispatchStatusEvent(
        fromStatus: fromStatus,
        toStatus: assignedTrip.status,
        createdAt: createdAt,
        metadata: <String, dynamic>{
          'source': 'assign_call',
          'assignment_id': assignment.id,
          'driver_id': assignment.driverId,
        },
      ),
    );
  }

  void _appendHistoryEvent(DispatchStatusEvent event) {
    final eventId = (event.id ?? '').trim();
    final alreadyExists = _history.any((existing) {
      final existingId = (existing.id ?? '').trim();
      if (eventId.isNotEmpty && existingId == eventId) {
        return true;
      }
      return existing.toStatus == event.toStatus &&
          (existing.createdAt ?? '') == (event.createdAt ?? '') &&
          (existing.fromStatus ?? '') == (event.fromStatus ?? '');
    });
    if (alreadyExists) {
      return;
    }
    setState(() {
      _history.add(event);
    });
  }

  @override
  Widget build(BuildContext context) {
    final trip = _trip;
    if (_loading && trip == null) {
      return const Center(child: CircularProgressIndicator());
    }

    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 720),
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: <Widget>[
            Text(
              'Dispatch Trip',
              style: Theme.of(context).textTheme.headlineSmall,
            ),
            const SizedBox(height: 4),
            SelectableText('trip_id: ${widget.tripId}'),
            const SizedBox(height: 12),
            Wrap(
              spacing: 10,
              runSpacing: 10,
              children: <Widget>[
                FilledButton.tonal(
                  onPressed: _busy ? null : () => _loadTrip(showSpinner: false),
                  child: const Text('Refresh'),
                ),
              ],
            ),
            const SizedBox(height: 12),
            if (trip != null) ...<Widget>[
              _tripCard(context, trip),
              const SizedBox(height: 12),
              _statusCard(context, trip),
              const SizedBox(height: 12),
              _assignCard(context, trip),
              const SizedBox(height: 12),
              _historyCard(context),
            ],
            if ((_error ?? '').isNotEmpty) ...<Widget>[
              const SizedBox(height: 12),
              Text(
                _error!,
                style: TextStyle(color: Theme.of(context).colorScheme.error),
              ),
            ],
            if (_busy) ...<Widget>[
              const SizedBox(height: 12),
              const LinearProgressIndicator(),
            ],
          ],
        ),
      ),
    );
  }

  Widget _tripCard(BuildContext context, DispatchTrip trip) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Text(
              'Current Trip',
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: 8),
            _row('Status', trip.status),
            _row(
              'Pickup',
              '${trip.pickup.lat.toStringAsFixed(5)}, '
                  '${trip.pickup.lng.toStringAsFixed(5)}'
                  '${trip.pickup.address == null ? '' : ' (${trip.pickup.address})'}',
            ),
            _row(
              'Dropoff',
              '${trip.dropoff.lat.toStringAsFixed(5)}, '
                  '${trip.dropoff.lng.toStringAsFixed(5)}'
                  '${trip.dropoff.address == null ? '' : ' (${trip.dropoff.address})'}',
            ),
            if ((trip.notes ?? '').isNotEmpty) _row('Notes', trip.notes!),
            if ((trip.scheduledAt ?? '').isNotEmpty)
              _row('Scheduled', trip.scheduledAt!),
          ],
        ),
      ),
    );
  }

  Widget _statusCard(BuildContext context, DispatchTrip trip) {
    final nextStatuses =
        _statusTransitions[trip.status.toLowerCase()] ?? const <String>[];
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Text(
              'Status Transitions',
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: 8),
            if (nextStatuses.isEmpty)
              const Text('No transitions available from current status.')
            else
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: <Widget>[
                  for (final nextStatus in nextStatuses)
                    FilledButton(
                      onPressed: _busy ? null : () => _transitionTo(nextStatus),
                      child: Text(nextStatus),
                    ),
                ],
              ),
          ],
        ),
      ),
    );
  }

  Widget _assignCard(BuildContext context, DispatchTrip trip) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Text(
              'Assign Driver',
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: 8),
            TextField(
              controller: _driverIdController,
              enabled: !_busy,
              decoration: const InputDecoration(
                labelText: 'driver_id',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 8),
            FilledButton.tonal(
              onPressed: _busy ? null : _assignDriver,
              child: const Text('Assign'),
            ),
            if (_assignment != null) ...<Widget>[
              const SizedBox(height: 8),
              _row('Assignment ID', _assignment!.id),
              _row('Driver', _assignment!.driverId),
              _row('Assignment Status', _assignment!.status),
            ],
            const SizedBox(height: 4),
            Text(
              'Allowed when trip is created or searching.',
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ],
        ),
      ),
    );
  }

  Widget _historyCard(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Text(
              'Status History',
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: 8),
            if (_history.isEmpty)
              const Text('No status events yet.')
            else
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: _history
                    .map((event) {
                      final from = (event.fromStatus ?? '').trim();
                      final transition = from.isEmpty
                          ? event.toStatus
                          : '$from -> ${event.toStatus}';
                      final createdAt = (event.createdAt ?? '').trim();
                      return Padding(
                        padding: const EdgeInsets.only(bottom: 8),
                        child: Text(
                          createdAt.isEmpty
                              ? transition
                              : '$transition ($createdAt)',
                        ),
                      );
                    })
                    .toList(growable: false),
              ),
          ],
        ),
      ),
    );
  }

  Widget _row(String label, String value) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          SizedBox(
            width: 110,
            child: Text(
              label,
              style: const TextStyle(fontWeight: FontWeight.w600),
            ),
          ),
          Expanded(child: Text(value)),
        ],
      ),
    );
  }
}
