import 'package:flutter/material.dart';

import '../../core/api/api_client.dart';
import '../../core/api/api_errors.dart';
import '../../core/api/api_paths.dart';
import '../shared/ride_snapshot_card.dart';
import '../shared/ride_timeline_widget.dart';

class DriverRideOpsScreen extends StatefulWidget {
  const DriverRideOpsScreen({
    super.key,
    required this.apiClient,
    this.initialRideId,
  });

  final ApiClient apiClient;
  final String? initialRideId;

  @override
  State<DriverRideOpsScreen> createState() => _DriverRideOpsScreenState();
}

class _DriverRideOpsScreenState extends State<DriverRideOpsScreen> {
  late final TextEditingController _rideIdController;
  bool _isBusy = false;
  Map<String, dynamic>? _snapshot;
  String? _inlineError;

  @override
  void initState() {
    super.initState();
    _rideIdController = TextEditingController(text: widget.initialRideId ?? '');
  }

  @override
  void dispose() {
    _rideIdController.dispose();
    super.dispose();
  }

  Future<void> _fetchSnapshot() async {
    final rideId = _rideIdController.text.trim();
    if (rideId.isEmpty) {
      _showErrorSnackBar('Enter a ride id first.');
      return;
    }
    await _run(
      operation: () async {
        final response = await widget.apiClient.get(
          ApiPaths.rideSnapshot(rideId),
        );
        if (!mounted) {
          return;
        }
        setState(() {
          _snapshot = response;
          _inlineError = null;
        });
      },
    );
  }

  Future<void> _acceptRide() async {
    await _postAndRefresh(
      pathBuilder: ApiPaths.rideAccept,
      body: const <String, dynamic>{},
    );
  }

  Future<void> _startRide() async {
    await _postAndRefresh(
      pathBuilder: ApiPaths.rideStart,
      body: const <String, dynamic>{},
    );
  }

  Future<void> _completeRide() async {
    await _postAndRefresh(
      pathBuilder: ApiPaths.rideComplete,
      body: const <String, dynamic>{'settlement_trigger': 'manual_override'},
    );
  }

  Future<void> _postAndRefresh({
    required String Function(String rideId) pathBuilder,
    required Map<String, dynamic> body,
  }) async {
    final rideId = _rideIdController.text.trim();
    if (rideId.isEmpty) {
      _showErrorSnackBar('Enter a ride id first.');
      return;
    }
    await _run(
      operation: () async {
        await widget.apiClient.post(pathBuilder(rideId), body: body);
        final snapshot = await widget.apiClient.get(
          ApiPaths.rideSnapshot(rideId),
        );
        if (!mounted) {
          return;
        }
        setState(() {
          _snapshot = snapshot;
          _inlineError = null;
        });
      },
    );
  }

  Future<void> _run({required Future<void> Function() operation}) async {
    setState(() {
      _isBusy = true;
    });
    try {
      await operation();
    } catch (error) {
      if (!mounted) {
        return;
      }
      final message = _errorText(error);
      setState(() {
        _inlineError = message;
      });
      _showErrorSnackBar(message);
    } finally {
      if (mounted) {
        setState(() {
          _isBusy = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 720),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: <Widget>[
              Text(
                'Driver Ride Ops',
                style: Theme.of(context).textTheme.headlineSmall,
              ),
              const SizedBox(height: 16),
              TextField(
                controller: _rideIdController,
                decoration: const InputDecoration(
                  labelText: 'ride_id',
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 12),
              Wrap(
                spacing: 10,
                runSpacing: 10,
                children: <Widget>[
                  FilledButton.tonal(
                    onPressed: _isBusy ? null : _fetchSnapshot,
                    child: const Text('Fetch Snapshot'),
                  ),
                  FilledButton(
                    onPressed: _isBusy ? null : _acceptRide,
                    child: const Text('Accept Ride'),
                  ),
                  FilledButton(
                    onPressed: _isBusy ? null : _startRide,
                    child: const Text('Start Ride'),
                  ),
                  FilledButton(
                    onPressed: _isBusy ? null : _completeRide,
                    child: const Text('Complete Ride'),
                  ),
                ],
              ),
              if (_isBusy) ...<Widget>[
                const SizedBox(height: 12),
                const LinearProgressIndicator(),
              ],
              if (_inlineError != null) ...<Widget>[
                const SizedBox(height: 12),
                Text(
                  _inlineError!,
                  style: TextStyle(color: Theme.of(context).colorScheme.error),
                ),
              ],
              const SizedBox(height: 16),
              if (_snapshot != null) ...<Widget>[
                RideTimelineWidget(snapshot: _snapshot!),
                const SizedBox(height: 12),
                RideSnapshotCard(snapshot: _snapshot!),
              ],
            ],
          ),
        ),
      ),
    );
  }

  void _showErrorSnackBar(Object message) {
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(message.toString())));
  }
}

String _errorText(Object error) {
  return formatApiError(error);
}
