import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../../core/api/api_errors.dart';
import '../data/dispatch_repository.dart';
import '../models/dispatch_models.dart';

class DispatchTripCreateScreen extends StatefulWidget {
  const DispatchTripCreateScreen({super.key, required this.repository});

  final DispatchRepository repository;

  @override
  State<DispatchTripCreateScreen> createState() =>
      _DispatchTripCreateScreenState();
}

class _DispatchTripCreateScreenState extends State<DispatchTripCreateScreen> {
  final TextEditingController _pickupLatController = TextEditingController(
    text: '6.455',
  );
  final TextEditingController _pickupLngController = TextEditingController(
    text: '3.384',
  );
  final TextEditingController _pickupAddressController = TextEditingController(
    text: 'Lagos Island',
  );
  final TextEditingController _dropoffLatController = TextEditingController(
    text: '6.6018',
  );
  final TextEditingController _dropoffLngController = TextEditingController(
    text: '3.3515',
  );
  final TextEditingController _dropoffAddressController = TextEditingController(
    text: 'Ikeja',
  );
  final TextEditingController _notesController = TextEditingController();

  DispatchQuote? _quote;
  bool _loadingQuote = false;
  bool _loadingCreate = false;
  String? _error;

  @override
  void dispose() {
    _pickupLatController.dispose();
    _pickupLngController.dispose();
    _pickupAddressController.dispose();
    _dropoffLatController.dispose();
    _dropoffLngController.dispose();
    _dropoffAddressController.dispose();
    _notesController.dispose();
    super.dispose();
  }

  Future<void> _getQuote() async {
    final coords = _readCoordinates();
    if (coords == null) {
      return;
    }
    setState(() {
      _loadingQuote = true;
      _error = null;
    });
    try {
      final quote = await widget.repository.createQuote(
        pickupLat: coords.pickupLat,
        pickupLng: coords.pickupLng,
        dropoffLat: coords.dropoffLat,
        dropoffLng: coords.dropoffLng,
      );
      if (!mounted) {
        return;
      }
      setState(() {
        _quote = quote;
      });
    } catch (error) {
      if (!mounted) {
        return;
      }
      setState(() {
        _error = formatApiError(error);
      });
    } finally {
      if (mounted) {
        setState(() {
          _loadingQuote = false;
        });
      }
    }
  }

  Future<void> _createTrip() async {
    final coords = _readCoordinates();
    if (coords == null) {
      return;
    }
    setState(() {
      _loadingCreate = true;
      _error = null;
    });
    try {
      final trip = await widget.repository.createTrip(
        pickupLat: coords.pickupLat,
        pickupLng: coords.pickupLng,
        pickupAddress: _pickupAddressController.text.trim(),
        dropoffLat: coords.dropoffLat,
        dropoffLng: coords.dropoffLng,
        dropoffAddress: _dropoffAddressController.text.trim(),
        notes: _notesController.text.trim(),
      );
      if (!mounted) {
        return;
      }
      context.push('/dispatch/trips/${Uri.encodeComponent(trip.id)}');
    } catch (error) {
      if (!mounted) {
        return;
      }
      setState(() {
        _error = formatApiError(error);
      });
    } finally {
      if (mounted) {
        setState(() {
          _loadingCreate = false;
        });
      }
    }
  }

  _DispatchCoordinates? _readCoordinates() {
    final pickupLat = double.tryParse(_pickupLatController.text.trim());
    final pickupLng = double.tryParse(_pickupLngController.text.trim());
    final dropoffLat = double.tryParse(_dropoffLatController.text.trim());
    final dropoffLng = double.tryParse(_dropoffLngController.text.trim());
    if (pickupLat == null ||
        pickupLng == null ||
        dropoffLat == null ||
        dropoffLng == null) {
      setState(() {
        _error = 'Please enter valid numeric coordinates.';
      });
      return null;
    }
    return _DispatchCoordinates(
      pickupLat: pickupLat,
      pickupLng: pickupLng,
      dropoffLat: dropoffLat,
      dropoffLng: dropoffLng,
    );
  }

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 680),
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: <Widget>[
            Text(
              'Create Dispatch Trip',
              style: Theme.of(context).textTheme.headlineSmall,
            ),
            const SizedBox(height: 8),
            Text('Pickup', style: textTheme.titleMedium),
            const SizedBox(height: 8),
            _coordRow(_pickupLatController, _pickupLngController),
            const SizedBox(height: 8),
            TextField(
              controller: _pickupAddressController,
              decoration: const InputDecoration(
                labelText: 'Pickup address',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 16),
            Text('Dropoff', style: textTheme.titleMedium),
            const SizedBox(height: 8),
            _coordRow(_dropoffLatController, _dropoffLngController),
            const SizedBox(height: 8),
            TextField(
              controller: _dropoffAddressController,
              decoration: const InputDecoration(
                labelText: 'Dropoff address',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 16),
            TextField(
              controller: _notesController,
              decoration: const InputDecoration(
                labelText: 'Notes (optional)',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 16),
            Row(
              children: <Widget>[
                Expanded(
                  child: FilledButton.tonal(
                    onPressed: _loadingQuote || _loadingCreate
                        ? null
                        : _getQuote,
                    child: _loadingQuote
                        ? const SizedBox(
                            width: 16,
                            height: 16,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Text('Get quote'),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: FilledButton(
                    onPressed: _loadingQuote || _loadingCreate
                        ? null
                        : _createTrip,
                    child: _loadingCreate
                        ? const SizedBox(
                            width: 16,
                            height: 16,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Text('Create trip'),
                  ),
                ),
              ],
            ),
            if (_quote != null) ...<Widget>[
              const SizedBox(height: 16),
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(12),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: <Widget>[
                      Text('Quote', style: textTheme.titleMedium),
                      const SizedBox(height: 8),
                      Text(
                        'Distance: ${_quote!.distanceKm.toStringAsFixed(2)} km',
                      ),
                      Text('ETA: ${_quote!.durationMinEst} min'),
                      Text(
                        'Price: ${_quote!.priceMinor} ${_quote!.currency} (minor units)',
                      ),
                    ],
                  ),
                ),
              ),
            ],
            if ((_error ?? '').isNotEmpty) ...<Widget>[
              const SizedBox(height: 12),
              Text(
                _error!,
                style: TextStyle(color: Theme.of(context).colorScheme.error),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _coordRow(
    TextEditingController latController,
    TextEditingController lngController,
  ) {
    return Row(
      children: <Widget>[
        Expanded(
          child: TextField(
            controller: latController,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            decoration: const InputDecoration(
              labelText: 'Latitude',
              border: OutlineInputBorder(),
            ),
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: TextField(
            controller: lngController,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            decoration: const InputDecoration(
              labelText: 'Longitude',
              border: OutlineInputBorder(),
            ),
          ),
        ),
      ],
    );
  }
}

class _DispatchCoordinates {
  const _DispatchCoordinates({
    required this.pickupLat,
    required this.pickupLng,
    required this.dropoffLat,
    required this.dropoffLng,
  });

  final double pickupLat;
  final double pickupLng;
  final double dropoffLat;
  final double dropoffLng;
}
