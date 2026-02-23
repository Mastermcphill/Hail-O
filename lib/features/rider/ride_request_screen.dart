import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../core/api/api_client.dart';
import '../../core/api/api_errors.dart';
import '../../core/api/api_paths.dart';

class RideRequestScreen extends StatefulWidget {
  const RideRequestScreen({super.key, required this.apiClient});

  final ApiClient apiClient;

  @override
  State<RideRequestScreen> createState() => _RideRequestScreenState();
}

class _RideRequestScreenState extends State<RideRequestScreen> {
  final _pickupController = TextEditingController();
  final _dropoffController = TextEditingController();
  final _passengersController = TextEditingController(text: '1');
  final _luggageCountController = TextEditingController(text: '0');
  final _scheduledDepartureController = TextEditingController();
  final _vehicleClassController = TextEditingController(text: 'sedan');
  final _baseFareMinorController = TextEditingController(text: '0');
  final _premiumMarkupMinorController = TextEditingController(text: '0');
  final _connectionFeeMinorController = TextEditingController(text: '0');

  String _tripScope = 'intra_city';
  bool _charterMode = false;
  bool _isSubmitting = false;
  bool _isEstimating = false;
  bool _isCheckingGate = true;
  int _distanceMeters = 12000;
  int _durationSeconds = 1800;
  String _distanceSource = 'stub';

  @override
  void initState() {
    super.initState();
    _scheduledDepartureController.text = DateTime.now()
        .toUtc()
        .add(const Duration(minutes: 10))
        .toIso8601String();
    _ensureNextOfKinGate();
  }

  @override
  void dispose() {
    _pickupController.dispose();
    _dropoffController.dispose();
    _passengersController.dispose();
    _luggageCountController.dispose();
    _scheduledDepartureController.dispose();
    _vehicleClassController.dispose();
    _baseFareMinorController.dispose();
    _premiumMarkupMinorController.dispose();
    _connectionFeeMinorController.dispose();
    super.dispose();
  }

  Future<void> _ensureNextOfKinGate() async {
    setState(() {
      _isCheckingGate = true;
    });
    try {
      await widget.apiClient.get(ApiPaths.meNextOfKin);
    } catch (error) {
      if (!mounted) {
        return;
      }
      final shouldGate =
          error is ApiException &&
          (error.statusCode == 404 || error.code == 'next_of_kin_not_set');
      if (shouldGate) {
        context.go('/rider/next-of-kin?return_to=/rider/request');
        return;
      }
      _showErrorSnackBar(error);
    } finally {
      if (mounted) {
        setState(() {
          _isCheckingGate = false;
        });
      }
    }
  }

  Future<void> _estimateDistance() async {
    final pickup = _pickupController.text.trim();
    final dropoff = _dropoffController.text.trim();
    if (pickup.isEmpty || dropoff.isEmpty) {
      _showSnackBar('Enter pickup and dropoff first.');
      return;
    }
    setState(() {
      _isEstimating = true;
    });
    try {
      setState(() {
        _distanceMeters = 12000;
        _durationSeconds = 1800;
        _distanceSource = 'stub';
      });
    } finally {
      if (mounted) {
        setState(() {
          _isEstimating = false;
        });
      }
    }
  }

  Future<void> _submit() async {
    FocusScope.of(context).unfocus();
    setState(() {
      _isSubmitting = true;
    });

    try {
      final pickup = _pickupController.text.trim();
      final dropoff = _dropoffController.text.trim();
      _distanceMeters = 12000;
      _durationSeconds = 1800;
      _distanceSource = 'stub';

      final scheduledAt = DateTime.parse(
        _scheduledDepartureController.text.trim(),
      ).toUtc();

      final payload = <String, dynamic>{
        'scheduled_departure_at': scheduledAt.toIso8601String(),
        'trip_scope': _tripScopeToBackendValue(_tripScope),
        'pickup': pickup,
        'dropoff': dropoff,
        'passengers': _parseInt(_passengersController.text),
        'luggage_count': _parseInt(_luggageCountController.text),
        'charter_mode': _charterMode,
        'distance_meters': _distanceMeters,
        'duration_seconds': _durationSeconds,
        'vehicle_class': _vehicleClassController.text.trim().isEmpty
            ? 'sedan'
            : _vehicleClassController.text.trim(),
        'base_fare_minor': _parseInt(_baseFareMinorController.text),
        'premium_markup_minor': _parseInt(_premiumMarkupMinorController.text),
        'connection_fee_minor': _parseInt(_connectionFeeMinorController.text),
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
        '?luggage_count=${_parseInt(_luggageCountController.text)}'
        '&charter_mode=$_charterMode',
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

  @override
  Widget build(BuildContext context) {
    if (_isCheckingGate) {
      return const Center(child: CircularProgressIndicator());
    }

    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 640),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: <Widget>[
              Text(
                'Create Ride Request',
                style: Theme.of(context).textTheme.headlineSmall,
              ),
              const SizedBox(height: 16),
              TextField(
                controller: _pickupController,
                decoration: const InputDecoration(
                  labelText: 'pickup',
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _dropoffController,
                decoration: const InputDecoration(
                  labelText: 'dropoff',
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 12),
              _LabeledTextField(
                controller: _passengersController,
                label: 'passengers',
              ),
              const SizedBox(height: 12),
              _LabeledTextField(
                controller: _luggageCountController,
                label: 'luggage_count',
              ),
              const SizedBox(height: 12),
              DropdownButtonFormField<String>(
                initialValue: _tripScope,
                decoration: const InputDecoration(
                  labelText: 'trip_scope',
                  border: OutlineInputBorder(),
                ),
                items: const <DropdownMenuItem<String>>[
                  DropdownMenuItem(
                    value: 'intra_city',
                    child: Text('intra_city'),
                  ),
                  DropdownMenuItem(
                    value: 'inter_city',
                    child: Text('inter_city'),
                  ),
                  DropdownMenuItem(
                    value: 'international',
                    child: Text('international'),
                  ),
                ],
                onChanged: (value) {
                  if (value == null) {
                    return;
                  }
                  setState(() {
                    _tripScope = value;
                  });
                },
              ),
              const SizedBox(height: 8),
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text('Charter mode'),
                value: _charterMode,
                onChanged: (value) {
                  setState(() {
                    _charterMode = value;
                  });
                },
              ),
              const SizedBox(height: 8),
              TextField(
                controller: _scheduledDepartureController,
                decoration: const InputDecoration(
                  labelText: 'scheduled_departure_at (UTC ISO)',
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 12),
              _LabeledTextField(
                controller: _vehicleClassController,
                label: 'vehicle_class',
                keyboardType: TextInputType.text,
              ),
              const SizedBox(height: 12),
              _LabeledTextField(
                controller: _baseFareMinorController,
                label: 'base_fare_minor',
              ),
              const SizedBox(height: 12),
              _LabeledTextField(
                controller: _premiumMarkupMinorController,
                label: 'premium_markup_minor',
              ),
              const SizedBox(height: 12),
              _LabeledTextField(
                controller: _connectionFeeMinorController,
                label: 'connection_fee_minor',
              ),
              const SizedBox(height: 16),
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(12),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: <Widget>[
                      Text('distance_meters: $_distanceMeters'),
                      const SizedBox(height: 4),
                      Text('duration_seconds: $_durationSeconds'),
                      const SizedBox(height: 4),
                      Text('distance_source: $_distanceSource'),
                      const SizedBox(height: 8),
                      FilledButton.tonal(
                        onPressed: _isEstimating ? null : _estimateDistance,
                        child: _isEstimating
                            ? const SizedBox(
                                height: 18,
                                width: 18,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                ),
                              )
                            : const Text('Estimate Distance'),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 16),
              FilledButton(
                onPressed: _isSubmitting ? null : _submit,
                child: _isSubmitting
                    ? const SizedBox(
                        height: 18,
                        width: 18,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Text('Submit Ride Request'),
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _showErrorSnackBar(Object error) {
    final message = formatApiError(error);
    _showSnackBar(message);
  }

  void _showSnackBar(String message) {
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(message)));
  }
}

class _LabeledTextField extends StatelessWidget {
  const _LabeledTextField({
    required this.controller,
    required this.label,
    this.keyboardType = TextInputType.number,
  });

  final TextEditingController controller;
  final String label;
  final TextInputType keyboardType;

  @override
  Widget build(BuildContext context) {
    return TextField(
      controller: controller,
      keyboardType: keyboardType,
      decoration: InputDecoration(
        labelText: label,
        border: const OutlineInputBorder(),
      ),
    );
  }
}

int _parseInt(String value) {
  return int.tryParse(value.trim()) ?? 0;
}

String _tripScopeToBackendValue(String value) {
  if (value == 'inter_city') {
    return 'inter_state';
  }
  return value;
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
