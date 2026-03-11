import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../core/api/api_client.dart';
import '../../core/api/api_errors.dart';
import '../../core/api/api_paths.dart';
import '../../features/rideshare/models/ride_search_draft.dart';
import '../../integrations/google/google_distance_service.dart';
import '../../theme/app_tokens.dart';
import '../../widgets/loading_overlay.dart';
import '../../widgets/premium_ui.dart';
import '../../widgets/ride_search_card.dart';
import '../../widgets/trust_badge.dart';

class RideRequestScreen extends StatefulWidget {
  const RideRequestScreen({
    super.key,
    required this.apiClient,
    this.draftEncoded,
    this.autoSearch = false,
  });

  final ApiClient apiClient;
  final String? draftEncoded;
  final bool autoSearch;

  @override
  State<RideRequestScreen> createState() => _RideRequestScreenState();
}

class _RideRequestScreenState extends State<RideRequestScreen> {
  final GoogleDistanceService _distanceService = GoogleDistanceService();

  late final RideSearchDraft _initialDraft;
  bool _isSubmitting = false;
  bool _isCheckingGate = true;
  bool _autoSearchTriggered = false;
  int _distanceMeters = 12000;
  int _durationSeconds = 1800;
  String _distanceSource = 'estimated';

  @override
  void initState() {
    super.initState();
    _initialDraft = RideSearchDraft.fromEncoded(widget.draftEncoded);
    _ensureNextOfKinGate();
  }

  String get _returnToPath {
    final draft = widget.draftEncoded;
    if ((draft ?? '').isEmpty) {
      return '/rider/request';
    }
    final params = <String, String>{
      'draft': draft!,
      if (widget.autoSearch) 'autosearch': '1',
    };
    return '/rider/request?${Uri(queryParameters: params).query}';
  }

  Future<void> _ensureNextOfKinGate() async {
    setState(() {
      _isCheckingGate = true;
    });
    try {
      await widget.apiClient.get(ApiPaths.meNextOfKin);
      if (!mounted) {
        return;
      }
      setState(() {
        _isCheckingGate = false;
      });
      if (widget.autoSearch &&
          !_autoSearchTriggered &&
          (_initialDraft.pickup.isNotEmpty ||
              _initialDraft.destination.isNotEmpty)) {
        _autoSearchTriggered = true;
        _submitDraft(_initialDraft);
      }
    } catch (error) {
      if (!mounted) {
        return;
      }
      final shouldGate =
          error is ApiException &&
          (error.statusCode == 404 || error.code == 'next_of_kin_not_set');
      if (shouldGate) {
        context.go(
          '/rider/next-of-kin?return_to=${Uri.encodeQueryComponent(_returnToPath)}',
        );
        return;
      }
      _showErrorSnackBar(error);
      setState(() {
        _isCheckingGate = false;
      });
    }
  }

  Future<void> _submitDraft(RideSearchDraft draft) async {
    if (draft.pickup.isEmpty || draft.destination.isEmpty) {
      _showSnackBar('Enter pickup and destination to search rides.');
      return;
    }
    FocusScope.of(context).unfocus();
    setState(() {
      _isSubmitting = true;
    });
    try {
      if (draft.isCrossBorder) {
        final hasCrossBorderDoc = await _hasCrossBorderDocument();
        if (hasCrossBorderDoc == false) {
          if (!mounted) {
            return;
          }
          context.go(
            '/rider/documents?return_to=${Uri.encodeQueryComponent(_returnToPath)}',
          );
          return;
        }
        if (hasCrossBorderDoc == null) {
          return;
        }
      }

      final estimate = await _distanceService.estimate(
        origin: draft.pickup,
        destination: draft.destination,
      );
      _distanceMeters = estimate.distanceMeters;
      _durationSeconds = estimate.durationSeconds;
      _distanceSource = estimate.source;

      final payload = <String, dynamic>{
        'scheduled_departure_at': draft.departureAt.toUtc().toIso8601String(),
        'trip_scope': draft.backendTripScope,
        'pickup': draft.pickup,
        'dropoff': draft.destination,
        'passengers': draft.passengerCount,
        'luggage_count': draft.luggageCount,
        'charter_mode': draft.charterMode,
        'distance_meters': _distanceMeters,
        'duration_seconds': _durationSeconds,
        'vehicle_class': draft.vehicleClassPreset,
        'base_fare_minor': draft.baseFareMinor,
        'premium_markup_minor': draft.premiumMarkupMinor,
        'connection_fee_minor': draft.connectionFeeMinor,
      };

      final response = await widget.apiClient.post(
        ApiPaths.ridesRequest,
        body: payload,
      );
      final rideId = _resolveRideId(response);
      if (rideId == null || rideId.isEmpty) {
        throw Exception('Ride request succeeded but no ride id was returned');
      }

      if (!mounted) {
        return;
      }
      context.go(
        '/rider/offers/${Uri.encodeComponent(rideId)}'
        '?luggage_count=${draft.luggageCount}'
        '&charter_mode=${draft.charterMode}'
        '&draft=${Uri.encodeQueryComponent(draft.toEncoded())}',
      );
    } catch (error) {
      if (!mounted) {
        return;
      }
      _showErrorSnackBar(error);
    } finally {
      if (mounted) {
        setState(() {
          _isSubmitting = false;
        });
      }
    }
  }

  Future<bool?> _hasCrossBorderDocument() async {
    try {
      final response = await widget.apiClient.get(
        '${ApiPaths.meDocuments}?valid_for=international',
      );
      return response['has_valid_cross_border_document'] == true;
    } catch (error) {
      if (!mounted) {
        return null;
      }
      _showErrorSnackBar(error);
      return null;
    }
  }

  @override
  Widget build(BuildContext context) {
    return LoadingOverlay(
      isLoading: _isSubmitting || _isCheckingGate,
      message: _isCheckingGate
          ? 'Checking rider readiness...'
          : 'Searching live rides...',
      child: SingleChildScrollView(
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
                              label: 'Live ride search',
                              icon: Icons.search_rounded,
                              backgroundColor: Color(0x24FFFFFF),
                              foregroundColor: Colors.white,
                            ),
                            const SizedBox(height: HailoSpacing.lg),
                            Text(
                              'Search premium rides with the real booking engine.',
                              style: Theme.of(context).textTheme.headlineMedium
                                  ?.copyWith(
                                    color: Colors.white,
                                    fontWeight: FontWeight.w800,
                                  ),
                            ),
                            const SizedBox(height: HailoSpacing.md),
                            Text(
                              'This step uses the authenticated ride request API, preserves passenger readiness gates, and sends you into live ride matches.',
                              style: Theme.of(context).textTheme.bodyLarge
                                  ?.copyWith(
                                    color: Colors.white.withValues(alpha: 0.88),
                                  ),
                            ),
                            const SizedBox(height: HailoSpacing.lg),
                            Wrap(
                              spacing: HailoSpacing.xs,
                              runSpacing: HailoSpacing.xs,
                              children: const <Widget>[
                                TrustBadge(
                                  label: 'Escrow protected booking',
                                  icon: Icons.lock_clock_outlined,
                                  tint: Colors.white,
                                ),
                                TrustBadge(
                                  label: 'Seat tier aware',
                                  icon: Icons.event_seat_outlined,
                                  tint: Colors.white,
                                ),
                              ],
                            ),
                          ],
                        ),
                      ),
                      ConstrainedBox(
                        constraints: const BoxConstraints(maxWidth: 360),
                        child: PremiumPanel(
                          padding: const EdgeInsets.all(HailoSpacing.md),
                          gradient: LinearGradient(
                            colors: <Color>[
                              Colors.white.withValues(alpha: 0.12),
                              Colors.white.withValues(alpha: 0.05),
                            ],
                            begin: Alignment.topLeft,
                            end: Alignment.bottomRight,
                          ),
                          borderColor: Colors.white.withValues(alpha: 0.14),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: <Widget>[
                              Text(
                                'Route intelligence',
                                style: Theme.of(context).textTheme.titleMedium
                                    ?.copyWith(
                                      color: Colors.white,
                                      fontWeight: FontWeight.w700,
                                    ),
                              ),
                              const SizedBox(height: HailoSpacing.md),
                              _MetricLine(
                                label: 'Distance',
                                value:
                                    '${(_distanceMeters / 1000).toStringAsFixed(1)} km',
                              ),
                              const SizedBox(height: HailoSpacing.xs),
                              _MetricLine(
                                label: 'Travel time',
                                value:
                                    '${(_durationSeconds / 60).round()} mins',
                              ),
                              const SizedBox(height: HailoSpacing.xs),
                              _MetricLine(
                                label: 'Estimate source',
                                value: _distanceSource,
                              ),
                            ],
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: HailoSpacing.section),
                RideSearchCard(
                  initialDraft: _initialDraft,
                  caption: 'Search live rides',
                  primaryLabel: 'Search rides',
                  showCharterMode: true,
                  onSubmit: _submitDraft,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  void _showErrorSnackBar(Object error) {
    _showSnackBar(formatApiError(error));
  }

  void _showSnackBar(String message) {
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(message)));
  }
}

class _MetricLine extends StatelessWidget {
  const _MetricLine({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: <Widget>[
        SizedBox(
          width: 110,
          child: Text(
            label,
            style: Theme.of(context).textTheme.labelMedium?.copyWith(
              color: Colors.white.withValues(alpha: 0.78),
            ),
          ),
        ),
        Expanded(
          child: Text(
            value,
            style: Theme.of(context).textTheme.titleSmall?.copyWith(
              color: Colors.white,
              fontWeight: FontWeight.w700,
            ),
          ),
        ),
      ],
    );
  }
}

String? _resolveRideId(Map<String, dynamic> response) {
  final directRideId = response['ride_id'];
  if (directRideId is String && directRideId.isNotEmpty) {
    return directRideId;
  }
  final directId = response['id'];
  if (directId is String && directId.isNotEmpty) {
    return directId;
  }
  final nestedRide = response['ride'];
  if (nestedRide is Map) {
    final nestedId = nestedRide['id'];
    if (nestedId is String && nestedId.isNotEmpty) {
      return nestedId;
    }
  }
  return null;
}
