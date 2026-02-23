import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../core/api/api_client.dart';
import '../../core/api/api_errors.dart';
import '../../core/api/api_paths.dart';
import '../../core/api/mock_backend_store.dart';
import '../../core/util/ids.dart';
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
  final TextEditingController _seatCountController = TextEditingController(
    text: '1',
  );

  List<Map<String, dynamic>> _seats = <Map<String, dynamic>>[];
  Set<String> _selectedSeatIds = <String>{};
  int _seatCount = 1;
  bool _isLoading = true;
  bool _isSaving = false;
  String? _errorMessage;

  @override
  void initState() {
    super.initState();
    _loadSeats();
  }

  @override
  void dispose() {
    _seatCountController.dispose();
    super.dispose();
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
      _selectedSeatIds = _availableSeatIds().toSet();
      _setSeatCount(_selectedSeatIds.length);
    } else {
      final persisted = MockBackendStore.selectedSeatIdsByRideId[widget.rideId];
      if (persisted != null && persisted.isNotEmpty) {
        _selectedSeatIds = persisted.toSet();
        _setSeatCount(_selectedSeatIds.length);
      } else {
        _setSeatCount(1);
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
      if (_selectedSeatIds.length > _seatCount) {
        _setSeatCount(_selectedSeatIds.length);
      }
    });
  }

  void _setSeatCount(int value) {
    final clamped = _clampSeatCount(value);
    _seatCount = clamped;
    _seatCountController.text = clamped.toString();
  }

  void _onSeatCountChanged(String value) {
    final parsed = int.tryParse(value.trim());
    if (parsed == null) {
      return;
    }
    setState(() {
      _setSeatCount(parsed);
    });
  }

  Future<void> _confirmSelection() async {
    final resolvedSeatIds = _resolvedSeatIdsForCheckout();
    if (resolvedSeatIds.isEmpty) {
      _showSnackBar('Select at least one available seat.');
      return;
    }

    setState(() {
      _isSaving = true;
      _errorMessage = null;
    });

    final basePriceMinor = _resolvedBasePriceMinor(
      widget.rideId,
      widget.offerPriceMinor,
    );
    final pricingMinor = _calculatePricingMinor(
      selectedSeatIds: resolvedSeatIds.toSet(),
      basePriceMinor: basePriceMinor,
      charterMode: widget.charterMode,
    );
    final payload = <String, dynamic>{
      'seat_ids': resolvedSeatIds,
      'pricing_minor': pricingMinor,
    };

    Map<String, dynamic> response = <String, dynamic>{};
    try {
      response = await widget.apiClient.post(
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
    }

    final purchaseId = _resolvePurchaseId(response);
    MockBackendStore.selectedSeatIdsByRideId[widget.rideId] = resolvedSeatIds;
    final existingPurchase =
        MockBackendStore.purchasesById[purchaseId] ?? <String, dynamic>{};
    MockBackendStore.purchasesById[purchaseId] = <String, dynamic>{
      ...existingPurchase,
      'purchase_id': purchaseId,
      'ride_id': widget.rideId,
      'seat_ids': resolvedSeatIds,
      'seat_count': _seatCount,
      'pricing_minor': pricingMinor,
      'status': 'CONFIRMED',
    };

    if (!mounted) {
      return;
    }
    context.push(
      '/rider/timeline/${Uri.encodeComponent(purchaseId)}'
      '?rideId=${Uri.encodeQueryComponent(widget.rideId)}',
    );
  }

  List<String> _resolvedSeatIdsForCheckout() {
    final available = _availableSeatIds();
    if (available.isEmpty) {
      return <String>[];
    }

    if (widget.charterMode) {
      final takeCount = available.length.clamp(1, 50);
      return available.take(takeCount).toList(growable: false);
    }

    final target = _clampSeatCount(_seatCount);
    final selectedOrdered = available
        .where((seatId) => _selectedSeatIds.contains(seatId))
        .toList(growable: true);

    if (selectedOrdered.length > target) {
      return selectedOrdered.take(target).toList(growable: false);
    }

    if (selectedOrdered.length < target) {
      for (final seatId in available) {
        if (!selectedOrdered.contains(seatId)) {
          selectedOrdered.add(seatId);
        }
        if (selectedOrdered.length >= target) {
          break;
        }
      }
    }

    if (selectedOrdered.isEmpty) {
      selectedOrdered.add(available.first);
    }
    return selectedOrdered.toList(growable: false);
  }

  List<String> _availableSeatIds() {
    return _seats
        .where((seat) => _isSeatAvailable(seat))
        .map(_seatId)
        .where((id) => id.isNotEmpty)
        .toList(growable: false);
  }

  @override
  Widget build(BuildContext context) {
    final resolvedSeatIds = _resolvedSeatIdsForCheckout();
    final basePrice = _resolvedBasePriceMinor(
      widget.rideId,
      widget.offerPriceMinor,
    );
    final pricingMinor = _calculatePricingMinor(
      selectedSeatIds: resolvedSeatIds.toSet(),
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
          else
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: <Widget>[
                  Expanded(
                    child: ListView(
                      children: <Widget>[
                        Card(
                          child: Padding(
                            padding: const EdgeInsets.all(12),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.stretch,
                              children: <Widget>[
                                Text(
                                  'Seat Count (1..50)',
                                  style: Theme.of(context).textTheme.titleSmall,
                                ),
                                const SizedBox(height: 8),
                                Row(
                                  children: <Widget>[
                                    IconButton(
                                      key: const Key('seat_count_decrement'),
                                      onPressed: widget.charterMode
                                          ? null
                                          : () {
                                              setState(() {
                                                _setSeatCount(_seatCount - 1);
                                              });
                                            },
                                      icon: const Icon(
                                        Icons.remove_circle_outline,
                                      ),
                                    ),
                                    SizedBox(
                                      width: 90,
                                      child: TextField(
                                        key: const Key('seat_count_field'),
                                        controller: _seatCountController,
                                        enabled: !widget.charterMode,
                                        keyboardType: TextInputType.number,
                                        onChanged: _onSeatCountChanged,
                                        decoration: const InputDecoration(
                                          border: OutlineInputBorder(),
                                          isDense: true,
                                        ),
                                      ),
                                    ),
                                    IconButton(
                                      key: const Key('seat_count_increment'),
                                      onPressed: widget.charterMode
                                          ? null
                                          : () {
                                              setState(() {
                                                _setSeatCount(_seatCount + 1);
                                              });
                                            },
                                      icon: const Icon(
                                        Icons.add_circle_outline,
                                      ),
                                    ),
                                    const SizedBox(width: 8),
                                    Expanded(
                                      child: Text(
                                        widget.charterMode
                                            ? 'Locked in charter mode'
                                            : 'Used to auto-fill seats if not manually selected.',
                                      ),
                                    ),
                                  ],
                                ),
                              ],
                            ),
                          ),
                        ),
                        const SizedBox(height: 12),
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
                                  label: 'seat_count',
                                  value: _seatCount.toString(),
                                ),
                                _PricingRow(
                                  label: 'resolved_seats',
                                  value: resolvedSeatIds.join(', '),
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
                            style: TextStyle(
                              color: Theme.of(context).colorScheme.error,
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                  const SizedBox(height: 12),
                  FilledButton(
                    key: const Key('confirm_seats_button'),
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
              ),
            ),
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
  return '';
}

bool _isSeatAvailable(Map<String, dynamic> seat) {
  final value = seat['is_available'];
  if (value is bool) {
    return value;
  }
  return true;
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

String _resolvePurchaseId(Map<String, dynamic> response) {
  final direct = response['purchase_id'];
  if (direct is String && direct.trim().isNotEmpty) {
    return direct.trim();
  }
  final nested = response['purchase'];
  if (nested is Map) {
    final nestedId = nested['id'] ?? nested['purchase_id'];
    if (nestedId is String && nestedId.trim().isNotEmpty) {
      return nestedId.trim();
    }
  }
  return newRequestId();
}

int _clampSeatCount(int value) {
  if (value < 1) {
    return 1;
  }
  if (value > 50) {
    return 50;
  }
  return value;
}
