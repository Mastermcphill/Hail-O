import 'dart:async';

import 'package:flutter/material.dart';

import '../../core/api/api_client.dart';
import '../../core/api/api_errors.dart';
import '../../core/api/api_paths.dart';
import '../../core/util/polling.dart';
import '../../domain/models/latlng.dart';
import '../../integrations/mapbox/mapbox_map_widget.dart';
import '../../theme/app_tokens.dart';
import '../../widgets/premium_ui.dart';
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
        _errorMessage = formatApiError(error);
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
      ).showSnackBar(SnackBar(content: Text(formatApiError(error))));
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
    return SingleChildScrollView(
      padding: const EdgeInsets.all(HailoSpacing.lg),
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 1080),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: <Widget>[
              PremiumPanel(
                gradient: context.hailoTokens.heroGradient,
                borderColor: Colors.white.withValues(alpha: 0.10),
                child: Wrap(
                  spacing: HailoSpacing.xl,
                  runSpacing: HailoSpacing.lg,
                  children: <Widget>[
                    ConstrainedBox(
                      constraints: const BoxConstraints(maxWidth: 520),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: <Widget>[
                          const PremiumPill(
                            label: 'Trip tracking',
                            icon: Icons.timeline_rounded,
                            backgroundColor: Color(0x24FFFFFF),
                            foregroundColor: Colors.white,
                          ),
                          const SizedBox(height: HailoSpacing.lg),
                          Text(
                            'Track assignment, departure, and arrival in one premium surface.',
                            style: Theme.of(context).textTheme.headlineMedium
                                ?.copyWith(
                                  color: Colors.white,
                                  fontWeight: FontWeight.w800,
                                ),
                          ),
                        ],
                      ),
                    ),
                    Wrap(
                      spacing: HailoSpacing.sm,
                      runSpacing: HailoSpacing.sm,
                      children: <Widget>[
                        FilledButton.tonal(
                          onPressed: _isLoading ? null : _fetchSnapshot,
                          child: const Text('Refresh'),
                        ),
                        FilledButton(
                          onPressed: (_isMutating || _isLoading)
                              ? null
                              : _cancelRide,
                          child: _isMutating
                              ? const SizedBox(
                                  width: 18,
                                  height: 18,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                  ),
                                )
                              : const Text('Cancel ride'),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              const SizedBox(height: HailoSpacing.section),
              SizedBox(
                height: 260,
                child: PremiumPanel(
                  padding: const EdgeInsets.all(HailoSpacing.sm),
                  child: ClipRRect(
                    borderRadius: HailoRadii.md,
                    child: const MapboxMapWidget(
                      initialCenter: LatLng(
                        latitude: 6.5244,
                        longitude: 3.3792,
                      ),
                      initialZoom: 10,
                    ),
                  ),
                ),
              ),
              const SizedBox(height: HailoSpacing.lg),
              if (_isLoading && _snapshot == null)
                const Center(child: CircularProgressIndicator())
              else if (_snapshot != null) ...<Widget>[
                RideTimelineWidget(snapshot: _snapshot!),
                const SizedBox(height: HailoSpacing.md),
                RideSnapshotCard(snapshot: _snapshot!),
              ],
              if (_errorMessage != null) ...<Widget>[
                const SizedBox(height: HailoSpacing.md),
                Text(
                  _errorMessage!,
                  style: TextStyle(color: Theme.of(context).colorScheme.error),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
