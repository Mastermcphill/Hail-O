import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../core/api/api_client.dart';
import '../../core/api/api_errors.dart';
import '../../core/api/api_paths.dart';
import '../../core/storage/token_storage.dart';
import 'next_of_kin_screen.dart';

class RideRequestScreen extends StatefulWidget {
  const RideRequestScreen({
    super.key,
    required this.apiClient,
    required this.tokenStorage,
  });

  final ApiClient apiClient;
  final TokenStorage tokenStorage;

  @override
  State<RideRequestScreen> createState() => _RideRequestScreenState();
}

class _RideRequestScreenState extends State<RideRequestScreen> {
  final _scheduledDepartureController = TextEditingController();
  final _distanceMetersController = TextEditingController(text: '12000');
  final _durationSecondsController = TextEditingController(text: '1800');
  final _luggageCountController = TextEditingController(text: '0');
  final _vehicleClassController = TextEditingController(text: 'sedan');
  final _baseFareMinorController = TextEditingController(text: '0');
  final _premiumMarkupMinorController = TextEditingController(text: '0');
  final _connectionFeeMinorController = TextEditingController(text: '0');

  String _tripScope = 'intra_city';
  bool _isSubmitting = false;
  bool _isCheckingNextOfKin = true;
  String? _gateErrorMessage;

  @override
  void initState() {
    super.initState();
    _scheduledDepartureController.text = DateTime.now()
        .toUtc()
        .add(const Duration(minutes: 10))
        .toIso8601String();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _ensureNextOfKin();
    });
  }

  @override
  void dispose() {
    _scheduledDepartureController.dispose();
    _distanceMetersController.dispose();
    _durationSecondsController.dispose();
    _luggageCountController.dispose();
    _vehicleClassController.dispose();
    _baseFareMinorController.dispose();
    _premiumMarkupMinorController.dispose();
    _connectionFeeMinorController.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    FocusScope.of(context).unfocus();
    setState(() {
      _isSubmitting = true;
    });

    try {
      final scheduledAt = DateTime.parse(
        _scheduledDepartureController.text.trim(),
      ).toUtc();
      final payload = <String, dynamic>{
        'scheduled_departure_at': scheduledAt.toIso8601String(),
        'trip_scope': _tripScopeToBackendValue(_tripScope),
        'distance_meters': _parseInt(_distanceMetersController.text),
        'duration_seconds': _parseInt(_durationSecondsController.text),
        'luggage_count': _parseInt(_luggageCountController.text),
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
      context.go('/rider/status/${Uri.encodeComponent(rideId)}');
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

  Future<void> _ensureNextOfKin() async {
    if (mounted) {
      setState(() {
        _isCheckingNextOfKin = true;
        _gateErrorMessage = null;
      });
    }

    try {
      final response = await widget.apiClient.get(ApiPaths.nextOfKin);
      if (_containsNextOfKin(response) || await _hasLocalNextOfKin()) {
        if (!mounted) {
          return;
        }
        setState(() {
          _isCheckingNextOfKin = false;
        });
        return;
      }
      await _goToNextOfKin();
    } catch (error) {
      if (_isNotFound(error)) {
        if (await _hasLocalNextOfKin()) {
          if (!mounted) {
            return;
          }
          setState(() {
            _isCheckingNextOfKin = false;
          });
          return;
        }
        await _goToNextOfKin();
        return;
      }
      if (!mounted) {
        return;
      }
      setState(() {
        _isCheckingNextOfKin = false;
        _gateErrorMessage = formatApiError(error);
      });
    }
  }

  Future<void> _goToNextOfKin() async {
    if (!mounted) {
      return;
    }
    final returnTo = Uri.encodeComponent('/rider/request');
    context.go('/rider/next-of-kin?returnTo=$returnTo');
  }

  Future<bool> _hasLocalNextOfKin() async {
    final encoded = await widget.tokenStorage.readValue(
      kNextOfKinLocalStorageKey,
    );
    if (encoded == null || encoded.trim().isEmpty) {
      return false;
    }
    try {
      final decoded = jsonDecode(encoded);
      final map = _asMap(decoded);
      return _hasAllNextOfKinFields(map);
    } catch (_) {
      return false;
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_isCheckingNextOfKin) {
      return const Center(child: CircularProgressIndicator());
    }

    if (_gateErrorMessage != null) {
      return Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 480),
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: <Widget>[
                Text(
                  'Could not verify next-of-kin',
                  style: Theme.of(context).textTheme.titleMedium,
                ),
                const SizedBox(height: 8),
                Text(
                  _gateErrorMessage!,
                  style: TextStyle(color: Theme.of(context).colorScheme.error),
                ),
                const SizedBox(height: 16),
                FilledButton(
                  onPressed: _ensureNextOfKin,
                  child: const Text('Retry'),
                ),
              ],
            ),
          ),
        ),
      );
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
                controller: _scheduledDepartureController,
                decoration: const InputDecoration(
                  labelText: 'scheduled_departure_at (UTC ISO)',
                  border: OutlineInputBorder(),
                ),
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
              const SizedBox(height: 12),
              _LabeledTextField(
                controller: _distanceMetersController,
                label: 'distance_meters',
              ),
              const SizedBox(height: 12),
              _LabeledTextField(
                controller: _durationSecondsController,
                label: 'duration_seconds',
              ),
              const SizedBox(height: 12),
              _LabeledTextField(
                controller: _luggageCountController,
                label: 'luggage_count',
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
              const SizedBox(height: 20),
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
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(_errorText(error))));
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

String _errorText(Object error) {
  return formatApiError(error);
}

bool _containsNextOfKin(Map<String, dynamic> response) {
  if (_hasAllNextOfKinFields(response)) {
    return true;
  }

  final nextOfKinMap = _asMap(response['next_of_kin']);
  if (_hasAllNextOfKinFields(nextOfKinMap)) {
    return true;
  }

  final dataMap = _asMap(response['data']);
  if (_hasAllNextOfKinFields(dataMap)) {
    return true;
  }

  final nestedMap = _asMap(dataMap['next_of_kin']);
  return _hasAllNextOfKinFields(nestedMap);
}

bool _hasAllNextOfKinFields(Map<String, dynamic> map) {
  return _readString(map['full_name']).isNotEmpty &&
      _readString(map['phone']).isNotEmpty &&
      _readString(map['relationship']).isNotEmpty;
}

bool _isNotFound(Object error) {
  return error is ApiException && error.statusCode == 404;
}

Map<String, dynamic> _asMap(dynamic value) {
  if (value is Map<String, dynamic>) {
    return value;
  }
  if (value is Map) {
    return value.map(
      (key, mapValue) => MapEntry<String, dynamic>(key.toString(), mapValue),
    );
  }
  return <String, dynamic>{};
}

String _readString(Object? value) {
  if (value is String) {
    return value.trim();
  }
  return '';
}
