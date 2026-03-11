import 'package:flutter/material.dart';

import '../../core/api/api_client.dart';
import '../../core/api/api_config.dart';
import '../../core/api/api_errors.dart';
import '../../core/api/api_paths.dart';
import '../../core/api/mock_backend_store.dart';
import '../../domain/models/latlng.dart';
import '../../integrations/mapbox/mapbox_map_widget.dart';
import '../../theme/app_tokens.dart';
import '../../widgets/premium_ui.dart';
import '../shared/ride_snapshot_card.dart';
import '../shared/ride_timeline_widget.dart';

class TimelineScreen extends StatefulWidget {
  const TimelineScreen({
    super.key,
    required this.apiClient,
    required this.purchaseId,
    this.rideId,
  });

  final ApiClient apiClient;
  final String purchaseId;
  final String? rideId;

  @override
  State<TimelineScreen> createState() => _TimelineScreenState();
}

class _TimelineScreenState extends State<TimelineScreen> {
  Map<String, dynamic> _snapshot = <String, dynamic>{};
  bool _isLoading = true;
  String? _errorMessage;

  @override
  void initState() {
    super.initState();
    _refresh();
  }

  Future<void> _refresh() async {
    if (mounted) {
      setState(() {
        _isLoading = true;
        _errorMessage = null;
      });
    }

    try {
      if (ApiConfig.mockMode) {
        _snapshot = _mockSnapshotForPurchase(widget.purchaseId, widget.rideId);
      } else {
        final rideId = widget.rideId ?? _rideIdFromPurchase(widget.purchaseId);
        if (rideId == null || rideId.isEmpty) {
          _snapshot = _mockSnapshotForPurchase(
            widget.purchaseId,
            widget.rideId,
          );
        } else {
          _snapshot = await widget.apiClient.get(ApiPaths.rideSnapshot(rideId));
        }
      }
    } catch (error) {
      _errorMessage = formatApiError(error);
      _snapshot = _mockSnapshotForPurchase(widget.purchaseId, widget.rideId);
    } finally {
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return RefreshIndicator(
      onRefresh: _refresh,
      child: ListView(
        padding: const EdgeInsets.all(HailoSpacing.lg),
        children: <Widget>[
          PremiumPanel(
            gradient: context.hailoTokens.heroGradient,
            borderColor: Colors.white.withValues(alpha: 0.10),
            child: Wrap(
              spacing: HailoSpacing.xl,
              runSpacing: HailoSpacing.lg,
              children: <Widget>[
                ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 560),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: <Widget>[
                      const PremiumPill(
                        label: 'Booking timeline',
                        icon: Icons.fact_check_outlined,
                        backgroundColor: Color(0x24FFFFFF),
                        foregroundColor: Colors.white,
                      ),
                      const SizedBox(height: HailoSpacing.lg),
                      Text(
                        'Follow booking protection, seat confirmation, and arrival progress.',
                        style: Theme.of(context).textTheme.headlineMedium
                            ?.copyWith(
                              color: Colors.white,
                              fontWeight: FontWeight.w800,
                            ),
                      ),
                    ],
                  ),
                ),
                PremiumPanel(
                  padding: const EdgeInsets.all(HailoSpacing.md),
                  gradient: LinearGradient(
                    colors: <Color>[
                      Colors.white.withValues(alpha: 0.12),
                      Colors.white.withValues(alpha: 0.05),
                    ],
                  ),
                  borderColor: Colors.white.withValues(alpha: 0.12),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: <Widget>[
                      Text(
                        'Purchase',
                        style: Theme.of(context).textTheme.labelLarge?.copyWith(
                          color: Colors.white.withValues(alpha: 0.76),
                        ),
                      ),
                      const SizedBox(height: HailoSpacing.xs),
                      Text(
                        widget.purchaseId,
                        style: Theme.of(context).textTheme.titleSmall?.copyWith(
                          color: Colors.white,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: HailoSpacing.section),
          SizedBox(
            height: 240,
            child: PremiumPanel(
              padding: const EdgeInsets.all(HailoSpacing.sm),
              child: ClipRRect(
                borderRadius: HailoRadii.md,
                child: const MapboxMapWidget(
                  initialCenter: LatLng(latitude: 6.5244, longitude: 3.3792),
                  initialZoom: 9.2,
                ),
              ),
            ),
          ),
          const SizedBox(height: HailoSpacing.lg),
          if (_isLoading)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: HailoSpacing.section),
              child: Center(child: CircularProgressIndicator()),
            )
          else ...<Widget>[
            RideTimelineWidget(
              key: const Key('timeline_widget'),
              snapshot: _snapshot,
            ),
            const SizedBox(height: HailoSpacing.md),
            RideSnapshotCard(snapshot: _snapshot),
          ],
          if (_errorMessage != null) ...<Widget>[
            const SizedBox(height: HailoSpacing.md),
            Text(
              _errorMessage!,
              style: TextStyle(color: Theme.of(context).colorScheme.error),
            ),
          ],
          const SizedBox(height: HailoSpacing.section),
        ],
      ),
    );
  }
}

Map<String, dynamic> _mockSnapshotForPurchase(
  String purchaseId,
  String? rideId,
) {
  final purchase =
      MockBackendStore.purchasesById[purchaseId] ?? <String, dynamic>{};
  final resolvedRideId = rideId ?? _rideIdFromPurchase(purchaseId);
  final seats = (purchase['seat_ids'] as List<dynamic>? ?? const <dynamic>[])
      .map((value) => value.toString())
      .toList(growable: false);

  return <String, dynamic>{
    'ok': true,
    'purchase_id': purchaseId,
    'ride_id': resolvedRideId,
    'status': _readString(purchase['status']).isEmpty
        ? 'CONFIRMED'
        : _readString(purchase['status']),
    'seat_ids': seats,
    'pricing_minor': purchase['pricing_minor'] ?? 0,
    'ride': <String, dynamic>{
      'id': resolvedRideId,
      'status': 'CONFIRMED',
      'state': 'CONFIRMED',
    },
  };
}

String? _rideIdFromPurchase(String purchaseId) {
  final purchase = MockBackendStore.purchasesById[purchaseId];
  if (purchase == null) {
    return null;
  }
  final rideId = purchase['ride_id'];
  if (rideId is String && rideId.trim().isNotEmpty) {
    return rideId.trim();
  }
  return null;
}

String _readString(Object? value) {
  if (value is String) {
    return value.trim();
  }
  return '';
}
