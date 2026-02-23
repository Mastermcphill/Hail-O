import 'package:flutter/material.dart';

import '../../core/api/api_client.dart';
import '../../core/api/api_errors.dart';
import '../../core/api/api_paths.dart';

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
  final _priceController = TextEditingController(text: '8000');
  final _genderController = TextEditingController();
  final _tribeController = TextEditingController();
  final _ratingController = TextEditingController(text: '4.7');
  final _vehicleClassController = TextEditingController(text: 'sedan');
  bool _isSubmitting = false;
  String? _statusMessage;
  String? _errorMessage;

  @override
  void initState() {
    super.initState();
    _rideIdController = TextEditingController(text: widget.initialRideId ?? '');
  }

  @override
  void dispose() {
    _rideIdController.dispose();
    _priceController.dispose();
    _genderController.dispose();
    _tribeController.dispose();
    _ratingController.dispose();
    _vehicleClassController.dispose();
    super.dispose();
  }

  Future<void> _submitOffer() async {
    final rideId = _rideIdController.text.trim();
    if (rideId.isEmpty) {
      _showSnackBar('ride_id is required.');
      return;
    }

    setState(() {
      _isSubmitting = true;
      _statusMessage = null;
      _errorMessage = null;
    });

    try {
      final response = await widget.apiClient.post(
        ApiPaths.rideOffers(rideId),
        body: <String, dynamic>{
          'price_minor': int.tryParse(_priceController.text.trim()) ?? 0,
          'gender': _genderController.text.trim(),
          'tribe': _tribeController.text.trim(),
          'star_rating': double.tryParse(_ratingController.text.trim()) ?? 4.7,
          'vehicle_class': _vehicleClassController.text.trim().isEmpty
              ? 'sedan'
              : _vehicleClassController.text.trim(),
          'luggage_supported': true,
        },
      );
      if (!mounted) {
        return;
      }
      setState(() {
        _statusMessage = response['mock_mode'] == true
            ? 'Offer saved in mock mode.'
            : 'Offer submitted.';
      });
      _showSnackBar(_statusMessage!);
    } catch (error) {
      if (!mounted) {
        return;
      }
      setState(() {
        _errorMessage = formatApiError(error);
      });
      _showSnackBar(_errorMessage!);
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
          constraints: const BoxConstraints(maxWidth: 560),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: <Widget>[
              Text(
                'Driver Offer Submission',
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
                controller: _priceController,
                keyboardType: TextInputType.number,
                decoration: const InputDecoration(
                  labelText: 'price_minor',
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
                controller: _vehicleClassController,
                decoration: const InputDecoration(
                  labelText: 'vehicle_class',
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 16),
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
              if (_statusMessage != null) ...<Widget>[
                const SizedBox(height: 8),
                Text(
                  _statusMessage!,
                  style: TextStyle(
                    color: Theme.of(context).colorScheme.primary,
                  ),
                ),
              ],
              if (_errorMessage != null) ...<Widget>[
                const SizedBox(height: 8),
                Text(
                  _errorMessage!,
                  style: TextStyle(color: Theme.of(context).colorScheme.error),
                ),
              ],
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
