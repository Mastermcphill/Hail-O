import 'package:flutter/material.dart';

import '../../core/api/api_client.dart';
import '../../core/api/api_errors.dart';
import '../../core/api/api_paths.dart';
import '../../core/api/mock_backend_store.dart';

class DriverOfferScreen extends StatefulWidget {
  const DriverOfferScreen({
    super.key,
    required this.apiClient,
    this.initialRideId,
  });

  final ApiClient apiClient;
  final String? initialRideId;

  @override
  State<DriverOfferScreen> createState() => _DriverOfferScreenState();
}

class _DriverOfferScreenState extends State<DriverOfferScreen> {
  late final TextEditingController _rideIdController;
  final TextEditingController _priceMinorController = TextEditingController(
    text: '5000',
  );
  final TextEditingController _ratingController = TextEditingController(
    text: '4.7',
  );
  final TextEditingController _genderController = TextEditingController(
    text: 'male',
  );
  final TextEditingController _tribeController = TextEditingController(
    text: 'yoruba',
  );
  String _vehicleClass = 'sedan';
  bool _isSubmitting = false;

  @override
  void initState() {
    super.initState();
    _rideIdController = TextEditingController(text: widget.initialRideId ?? '');
  }

  @override
  void dispose() {
    _rideIdController.dispose();
    _priceMinorController.dispose();
    _ratingController.dispose();
    _genderController.dispose();
    _tribeController.dispose();
    super.dispose();
  }

  Future<void> _submitOffer() async {
    FocusScope.of(context).unfocus();
    final rideId = _rideIdController.text.trim();
    if (rideId.isEmpty) {
      _showSnackBar('ride_id is required.');
      return;
    }

    final payload = <String, dynamic>{
      'price_minor': int.tryParse(_priceMinorController.text.trim()) ?? 0,
      'vehicle_class': _vehicleClass,
      'star_rating': double.tryParse(_ratingController.text.trim()) ?? 0,
      'gender': _genderController.text.trim(),
      'tribe': _tribeController.text.trim(),
    };

    setState(() {
      _isSubmitting = true;
    });

    try {
      await widget.apiClient.post(ApiPaths.rideOffers(rideId), body: payload);
      if (!mounted) {
        return;
      }
      _showSnackBar('Offer submitted.');
    } catch (error) {
      if (error is ApiException && error.statusCode == 404) {
        final mockOffer = <String, dynamic>{
          'offer_id': 'mock_offer_${DateTime.now().millisecondsSinceEpoch}',
          ...payload,
          'luggage_supported':
              _vehicleClass != 'hatchback' && _vehicleClass != 'sedan',
        };
        MockBackendStore.offersByRideId.putIfAbsent(
          rideId,
          () => <Map<String, dynamic>>[],
        );
        MockBackendStore.offersByRideId[rideId]!.add(mockOffer);
        if (!mounted) {
          return;
        }
        _showSnackBar('Offer saved in mock store.');
      } else {
        if (!mounted) {
          return;
        }
        _showSnackBar(formatApiError(error));
      }
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
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 620),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: <Widget>[
              Text(
                'Submit Offer',
                style: Theme.of(context).textTheme.headlineSmall,
              ),
              const SizedBox(height: 16),
              TextField(
                controller: _rideIdController,
                decoration: const InputDecoration(
                  labelText: 'ride_id',
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _priceMinorController,
                keyboardType: TextInputType.number,
                decoration: const InputDecoration(
                  labelText: 'price_minor',
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 12),
              DropdownButtonFormField<String>(
                initialValue: _vehicleClass,
                decoration: const InputDecoration(
                  labelText: 'vehicle_class',
                  border: OutlineInputBorder(),
                ),
                items: const <DropdownMenuItem<String>>[
                  DropdownMenuItem(value: 'sedan', child: Text('sedan')),
                  DropdownMenuItem(value: 'suv', child: Text('suv')),
                  DropdownMenuItem(
                    value: 'hatchback',
                    child: Text('hatchback'),
                  ),
                  DropdownMenuItem(value: 'van', child: Text('van')),
                ],
                onChanged: (value) {
                  if (value == null) {
                    return;
                  }
                  setState(() {
                    _vehicleClass = value;
                  });
                },
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _ratingController,
                keyboardType: const TextInputType.numberWithOptions(
                  decimal: true,
                ),
                decoration: const InputDecoration(
                  labelText: 'star_rating',
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _genderController,
                decoration: const InputDecoration(
                  labelText: 'gender (optional)',
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _tribeController,
                decoration: const InputDecoration(
                  labelText: 'tribe (optional)',
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 20),
              FilledButton(
                onPressed: _isSubmitting ? null : _submitOffer,
                child: _isSubmitting
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Text('Submit Offer'),
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
