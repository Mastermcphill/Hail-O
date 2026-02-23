import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../core/api/api_client.dart';
import '../../core/api/api_errors.dart';
import '../../core/api/api_paths.dart';
import '../../widgets/seat_layout_widget.dart';

class SeatSelectionScreen extends StatefulWidget {
  const SeatSelectionScreen({
    super.key,
    required this.apiClient,
    required this.rideId,
    this.charterMode = false,
  });

  final ApiClient apiClient;
  final String rideId;
  final bool charterMode;

  @override
  State<SeatSelectionScreen> createState() => _SeatSelectionScreenState();
}

class _SeatSelectionScreenState extends State<SeatSelectionScreen> {
  bool _isLoading = true;
  bool _isSubmitting = false;
  String? _errorMessage;
  List<String> _availableSeatIds = <String>[];
  Set<String> _selectedSeatIds = <String>{};
  int _basePriceMinor = 0;
  bool _charterMode = false;

  @override
  void initState() {
    super.initState();
    _charterMode = widget.charterMode;
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
      final seats = (response['seats'] as List<dynamic>? ?? const <dynamic>[])
          .whereType<Map>()
          .map(
            (item) => item.map(
              (key, value) => MapEntry<String, dynamic>(key.toString(), value),
            ),
          )
          .toList(growable: false);

      final available = seats
          .where((item) => item['available'] != false)
          .map((item) => item['seat_id']?.toString() ?? '')
          .where((id) => id.isNotEmpty)
          .toList(growable: false);

      final initiallySelected = seats
          .where((item) => item['selected'] == true)
          .map((item) => item['seat_id']?.toString() ?? '')
          .where((id) => id.isNotEmpty)
          .toSet();

      if (!mounted) {
        return;
      }
      setState(() {
        _availableSeatIds = available.isEmpty
            ? const <String>[
                'FRONT_RIGHT',
                'BACK_LEFT',
                'BACK_MIDDLE',
                'BACK_RIGHT',
              ]
            : available;
        _selectedSeatIds = initiallySelected;
        _basePriceMinor =
            (response['base_price_minor'] as num?)?.toInt() ?? 7000;
        _charterMode = response['charter_mode'] == true || widget.charterMode;
      });
    } catch (error) {
      if (!mounted) {
        return;
      }
      setState(() {
        _availableSeatIds = const <String>[
          'FRONT_RIGHT',
          'BACK_LEFT',
          'BACK_MIDDLE',
          'BACK_RIGHT',
        ];
        _basePriceMinor = 7000;
        _errorMessage = formatApiError(error);
      });
    } finally {
      if (mounted) {
        _applyCharterAutoSelect();
        setState(() {
          _isLoading = false;
        });
      }
    }
  }

  void _applyCharterAutoSelect() {
    if (!_charterMode) {
      return;
    }
    _selectedSeatIds = _availableSeatIds.toSet();
  }

  void _toggleSeat(String seatId) {
    if (_charterMode) {
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

  Future<void> _confirm() async {
    if (_selectedSeatIds.isEmpty) {
      _showSnackBar('Select at least one seat.');
      return;
    }
    setState(() {
      _isSubmitting = true;
      _errorMessage = null;
    });
    try {
      final pricingMinor = _computePricingMinor();
      await widget.apiClient.post(
        ApiPaths.rideSeatsSelect(widget.rideId),
        body: <String, dynamic>{
          'seat_ids': _selectedSeatIds.toList(growable: false),
          'pricing_minor': pricingMinor,
        },
      );
      if (!mounted) {
        return;
      }
      context.go('/rider/status/${Uri.encodeComponent(widget.rideId)}');
    } catch (error) {
      if (!mounted) {
        return;
      }
      setState(() {
        _errorMessage = formatApiError(error);
      });
      _showSnackBar(formatApiError(error));
    } finally {
      if (mounted) {
        setState(() {
          _isSubmitting = false;
        });
      }
    }
  }

  int _computePricingMinor() {
    if (_charterMode) {
      return (_basePriceMinor * 3).round();
    }
    var total = 0.0;
    for (final seatId in _selectedSeatIds) {
      var multiplier = 1.0;
      if (_isFrontSeat(seatId)) {
        multiplier += 0.10;
      }
      if (_isWindowSeat(seatId)) {
        multiplier += 0.05;
      }
      total += _basePriceMinor * multiplier;
    }
    return total.round();
  }

  bool _isFrontSeat(String seatId) {
    return seatId == 'FRONT_RIGHT';
  }

  bool _isWindowSeat(String seatId) {
    return seatId == 'FRONT_RIGHT' ||
        seatId == 'BACK_LEFT' ||
        seatId == 'BACK_RIGHT';
  }

  @override
  Widget build(BuildContext context) {
    final pricingMinor = _computePricingMinor();
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 720),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: <Widget>[
              Text(
                'Seat Selection',
                style: Theme.of(context).textTheme.headlineSmall,
              ),
              const SizedBox(height: 6),
              SelectableText('ride_id: ${widget.rideId}'),
              const SizedBox(height: 6),
              Text('charter_mode: $_charterMode'),
              const SizedBox(height: 12),
              if (_isLoading)
                const LinearProgressIndicator()
              else
                SeatLayoutWidget(
                  availableSeatIds: _availableSeatIds,
                  selectedSeatIds: _selectedSeatIds,
                  onToggleSeat: _toggleSeat,
                ),
              const SizedBox(height: 12),
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(12),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: <Widget>[
                      Text('base_price_minor: $_basePriceMinor'),
                      const SizedBox(height: 4),
                      Text(
                        _charterMode
                            ? 'Charter multiplier applied: +200%'
                            : 'Seat multipliers: front +10%, window +5%',
                      ),
                      const SizedBox(height: 4),
                      Text('pricing_minor: $pricingMinor'),
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
                onPressed: (_isLoading || _isSubmitting) ? null : _confirm,
                child: _isSubmitting
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
      ),
    );
  }

  void _showSnackBar(String message) {
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(message)));
  }
}
