import 'package:flutter/material.dart';

import '../../core/api/api_client.dart';
import '../../core/api/api_config.dart';
import '../../core/api/api_errors.dart';
import '../../core/api/api_paths.dart';
import '../../core/api/mock_backend_store.dart';
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
        padding: const EdgeInsets.all(16),
        children: <Widget>[
          Text(
            'Purchase Timeline',
            style: Theme.of(context).textTheme.headlineSmall,
          ),
          const SizedBox(height: 6),
          SelectableText('purchase_id: ${widget.purchaseId}'),
          if (widget.rideId != null && widget.rideId!.isNotEmpty)
            SelectableText('ride_id: ${widget.rideId}'),
          const SizedBox(height: 12),
          if (_isLoading)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 32),
              child: Center(child: CircularProgressIndicator()),
            )
          else ...<Widget>[
            RideTimelineWidget(
              key: const Key('timeline_widget'),
              snapshot: _snapshot,
            ),
            const SizedBox(height: 12),
            RideSnapshotCard(snapshot: _snapshot),
          ],
          if (_errorMessage != null) ...<Widget>[
            const SizedBox(height: 10),
            Text(
              _errorMessage!,
              style: TextStyle(color: Theme.of(context).colorScheme.error),
            ),
          ],
          const SizedBox(height: 24),
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
  final resolvedRideId = rideId ?? _readString(purchase['ride_id']);
  final seats = (purchase['seat_ids'] as List<dynamic>? ?? <dynamic>[])
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
