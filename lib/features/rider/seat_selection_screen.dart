import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../core/api/api_client.dart';
import '../../core/api/api_errors.dart';
import '../../core/api/api_paths.dart';
import '../../core/api/mock_backend_store.dart';
import '../../widgets/seat_layout_widget.dart';

class SeatSelectionScreen extends StatefulWidget {
  const SeatSelectionScreen({
    super.key,
    required this.apiClient,
    required this.rideId,
    required this.offerPriceMinor,
    required this.charterMode,
  });

  final ApiClient apiClient;
  final String rideId;
  final int offerPriceMinor;
  final bool charterMode;

  @override
  State<SeatSelectionScreen> createState() => _SeatSelectionScreenState();
}

class _SeatSelectionScreenState extends State<SeatSelectionScreen> {
  List<Map<String, dynamic>> _seats = <Map<String, dynamic>>[];
  Set<String> _selectedSeatIds = <String>{};
  bool _isLoading = true;
  bool _isSaving = false;
  String? _errorMessage;

  @override
  void initState() {
    super.initState();
    _loadSeats();
  }

  Future<void> _loadSeats() async {
    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });
    try {
      final response = await widget.apiClient.get(
        ApiPaths.rideSeats(widget.rideId),
      );
      final seats = _extractSeats(response);
      _seats = seats.isEmpty ? _mockSeats(widget.rideId) : seats;
    } catch (error) {
      if (error is ApiException && error.statusCode == 404) {
        _seats = _mockSeats(widget.rideId);
      } else {
        _errorMessage = formatApiError(error);
        _seats = _mockSeats(widget.rideId);
      }
    }

    if (widget.charterMode) {
      _selectedSeatIds = _seats.map(_seatId).toSet();
    } else {
      final persisted = MockBackendStore.selectedSeatIdsByRideId[widget.rideId];
      if (persisted != null && persisted.isNotEmpty) {
        _selectedSeatIds = persisted.toSet();
      }
    }

    if (mounted) {
      setState(() {
        _isLoading = false;
      });
    }
  }

  void _toggleSeat(String seatId) {
    if (widget.charterMode) {
      return;
    }
    setState(() {
      if (_selectedSeatIds.contains(seatId)) {
        _selectedSeatIds.remove(seatId);
      } else {
        _selectedSeatIds.add(seatId);
      }
    });
  }

  Future<void> _confirmSelection() async {
    if (_selectedSeatIds.isEmpty) {
      _showSnackBar('Select at least one seat.');
      return;
    }
    setState(() {
      _isSaving = true;
      _errorMessage = null;
    });

    final pricingMinor = _calculatePricingMinor(
      selectedSeatIds: _selectedSeatIds,
      basePriceMinor: _resolvedBasePriceMinor(
        widget.rideId,
        widget.offerPriceMinor,
      ),
      charterMode: widget.charterMode,
    );
    final payload = <String, dynamic>{
      'seat_ids': _selectedSeatIds.toList(growable: false),
      'pricing_minor': pricingMinor,
    };

    try {
      await widget.apiClient.post(
        ApiPaths.rideSeatSelect(widget.rideId),
        body: payload,
      );
    } catch (error) {
      if (error is! ApiException || error.statusCode != 404) {
        if (!mounted) {
          return;
        }
        setState(() {
          _errorMessage = formatApiError(error);
          _isSaving = false;
        });
        return;
      }
      MockBackendStore.selectedSeatIdsByRideId[widget.rideId] = _selectedSeatIds
          .toList(growable: false);
    }

    MockBackendStore.selectedSeatIdsByRideId[widget.rideId] = _selectedSeatIds
        .toList(growable: false);

    if (!mounted) {
      return;
    }
    context.go('/rider/status/${Uri.encodeComponent(widget.rideId)}');
  }

  @override
  Widget build(BuildContext context) {
    final basePrice = _resolvedBasePriceMinor(
      widget.rideId,
      widget.offerPriceMinor,
    );
    final pricingMinor = _calculatePricingMinor(
      selectedSeatIds: _selectedSeatIds,
      basePriceMinor: basePrice,
      charterMode: widget.charterMode,
    );

    return Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          Text(
            'Seat Selection',
            style: Theme.of(context).textTheme.headlineSmall,
          ),
          const SizedBox(height: 4),
          SelectableText('ride_id: ${widget.rideId}'),
          const SizedBox(height: 4),
          Text('charter_mode: ${widget.charterMode ? 'true' : 'false'}'),
          const SizedBox(height: 12),
          if (_isLoading)
            const Expanded(child: Center(child: CircularProgressIndicator()))
          else ...<Widget>[
            SeatLayoutWidget(
              seats: _seats,
              selectedSeatIds: _selectedSeatIds,
              onToggleSeat: _toggleSeat,
              readOnly: widget.charterMode,
            ),
            const SizedBox(height: 12),
            Card(
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: <Widget>[
                    _PricingRow(
                      label: 'base_price_minor',
                      value: basePrice.toString(),
                    ),
                    _PricingRow(
                      label: 'selected_seats',
                      value: _selectedSeatIds.join(', '),
                    ),
                    _PricingRow(
                      label: 'pricing_minor',
                      value: pricingMinor.toString(),
                    ),
                  ],
                ),
              ),
            ),
            if (_errorMessage != null) ...<Widget>[
              const SizedBox(height: 8),
              Text(
                _errorMessage!,
                style: TextStyle(color: Theme.of(context).colorScheme.error),
              ),
            ],
            const SizedBox(height: 12),
            FilledButton(
              onPressed: _isSaving ? null : _confirmSelection,
              child: _isSaving
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Text('Confirm Seats'),
            ),
          ],
        ],
      ),
    );
  }

  void _showSnackBar(String message) {
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(message)));
  }
}

class _PricingRow extends StatelessWidget {
  const _PricingRow({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Row(
        children: <Widget>[
          SizedBox(width: 150, child: Text(label)),
          Expanded(child: SelectableText(value.isEmpty ? '-' : value)),
        ],
      ),
    );
  }
}

List<Map<String, dynamic>> _extractSeats(Map<String, dynamic> response) {
  final direct = response['seats'];
  if (direct is List) {
    return _normalizeSeatList(direct);
  }
  final data = response['data'];
  if (data is List) {
    return _normalizeSeatList(data);
  }
  if (data is Map && data['seats'] is List) {
    return _normalizeSeatList(data['seats'] as List<dynamic>);
  }
  return <Map<String, dynamic>>[];
}

List<Map<String, dynamic>> _normalizeSeatList(List<dynamic> source) {
  return source
      .whereType<Map>()
      .map(
        (item) => item.map(
          (key, value) => MapEntry<String, dynamic>(key.toString(), value),
        ),
      )
      .toList(growable: false);
}

List<Map<String, dynamic>> _mockSeats(String rideId) {
  final stored = MockBackendStore.seatsByRideId[rideId];
  if (stored != null && stored.isNotEmpty) {
    return stored;
  }
  final mocked = <Map<String, dynamic>>[
    <String, dynamic>{'seat_id': 'FRONT_RIGHT', 'is_available': true},
    <String, dynamic>{'seat_id': 'BACK_LEFT', 'is_available': true},
    <String, dynamic>{'seat_id': 'BACK_MIDDLE', 'is_available': true},
    <String, dynamic>{'seat_id': 'BACK_RIGHT', 'is_available': true},
  ];
  MockBackendStore.seatsByRideId[rideId] = mocked;
  return mocked;
}

String _seatId(Map<String, dynamic> seat) {
  final raw = seat['seat_id'] ?? seat['id'];
  if (raw is String && raw.trim().isNotEmpty) {
    return raw.trim();
  }
  return 'UNKNOWN_SEAT';
}

int _resolvedBasePriceMinor(String rideId, int routeValue) {
  if (routeValue > 0) {
    return routeValue;
  }
  final accepted = MockBackendStore.acceptedOfferByRideId[rideId];
  if (accepted != null) {
    final price = accepted['price_minor'];
    if (price is int) {
      return price;
    }
    if (price is num) {
      return price.toInt();
    }
    if (price is String) {
      return int.tryParse(price.trim()) ?? 0;
    }
  }
  return 0;
}

int _calculatePricingMinor({
  required Set<String> selectedSeatIds,
  required int basePriceMinor,
  required bool charterMode,
}) {
  if (selectedSeatIds.isEmpty) {
    return 0;
  }

  var total = 0.0;
  for (final seatId in selectedSeatIds) {
    var multiplier = 1.0;
    if (seatId.contains('FRONT')) {
      multiplier += 0.10;
    }
    if (seatId.contains('LEFT') || seatId.contains('RIGHT')) {
      multiplier += 0.05;
    }
    total += basePriceMinor * multiplier;
  }

  if (charterMode) {
    total *= 3.0; // +200% placeholder multiplier.
  }
  return total.round();
}
