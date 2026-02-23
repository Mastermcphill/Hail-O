import 'dart:async';

import 'package:flutter/material.dart';

import '../../core/api/api_client.dart';
import '../../core/api/api_errors.dart';
import '../../core/api/api_paths.dart';
import '../../core/util/polling.dart';
import '../shared/ride_snapshot_card.dart';
import '../shared/ride_timeline_widget.dart';

class RideStatusScreen extends StatefulWidget {
  const RideStatusScreen({
    super.key,
    required this.apiClient,
    required this.rideId,
  });

  final ApiClient apiClient;
  final String rideId;

  @override
  State<RideStatusScreen> createState() => _RideStatusScreenState();
}

class _RideStatusScreenState extends State<RideStatusScreen>
    with WidgetsBindingObserver {
  final PollingController _pollingController = PollingController();
  Map<String, dynamic>? _snapshot;
  String? _errorMessage;
  bool _isLoading = true;
  bool _isMutating = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    unawaited(_startPolling());
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      unawaited(_startPolling());
      return;
    }
    if (state == AppLifecycleState.paused ||
        state == AppLifecycleState.detached ||
        state == AppLifecycleState.hidden ||
        state == AppLifecycleState.inactive) {
      _pollingController.stop();
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _pollingController.dispose();
    super.dispose();
  }

  Future<void> _startPolling() async {
    await _pollingController.start(
      interval: const Duration(seconds: 3),
      onPoll: () => _fetchSnapshot(silent: true),
      runImmediately: true,
    );
  }

  Future<void> _fetchSnapshot({bool silent = false}) async {
    if (!silent && mounted) {
      setState(() {
        _isLoading = true;
      });
    }
    try {
      final response = await widget.apiClient.get(
        ApiPaths.rideSnapshot(widget.rideId),
      );
      if (!mounted) {
        return;
      }
      setState(() {
        _snapshot = response;
        _errorMessage = null;
      });
    } catch (error) {
      if (!mounted) {
        return;
      }
      setState(() {
        _errorMessage = _errorText(error);
      });
    } finally {
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
      }
    }
  }

  Future<void> _cancelRide() async {
    setState(() {
      _isMutating = true;
    });

    try {
      await widget.apiClient.post(
        ApiPaths.rideCancel(widget.rideId),
        body: const <String, dynamic>{},
      );
      await _fetchSnapshot();
    } catch (error) {
      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(_errorText(error))));
    } finally {
      if (mounted) {
        setState(() {
          _isMutating = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          Text('Ride Status', style: Theme.of(context).textTheme.headlineSmall),
          const SizedBox(height: 4),
          SelectableText('ride_id: ${widget.rideId}'),
          const SizedBox(height: 12),
          Wrap(
            spacing: 12,
            runSpacing: 12,
            children: <Widget>[
              FilledButton.tonal(
                onPressed: _isLoading ? null : _fetchSnapshot,
                child: const Text('Refresh now'),
              ),
              FilledButton(
                onPressed: (_isMutating || _isLoading) ? null : _cancelRide,
                child: _isMutating
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Text('Cancel Ride'),
              ),
            ],
          ),
          const SizedBox(height: 16),
          if (_isLoading && _snapshot == null)
            const Expanded(child: Center(child: CircularProgressIndicator()))
          else if (_snapshot != null)
            Expanded(
              child: SingleChildScrollView(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: <Widget>[
                    RideTimelineWidget(snapshot: _snapshot!),
                    const SizedBox(height: 12),
                    RideSnapshotCard(snapshot: _snapshot!),
                  ],
                ),
              ),
            )
          else
            const SizedBox.shrink(),
          if (_errorMessage != null) ...<Widget>[
            const SizedBox(height: 12),
            Text(
              _errorMessage!,
              style: TextStyle(color: Theme.of(context).colorScheme.error),
            ),
          ],
        ],
      ),
    );
  }
}

String _errorText(Object error) {
  return formatApiError(error);
}
