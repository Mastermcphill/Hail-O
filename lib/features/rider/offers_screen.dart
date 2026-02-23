import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../core/api/api_client.dart';
import '../../core/api/api_errors.dart';
import '../../core/api/api_paths.dart';

class OffersScreen extends StatefulWidget {
  const OffersScreen({
    super.key,
    required this.apiClient,
    required this.rideId,
    int? initialLuggageCount,
    int? luggageCount,
    this.charterMode = false,
    this.expired = false,
  }) : initialLuggageCount = initialLuggageCount ?? luggageCount;

  final ApiClient apiClient;
  final String rideId;
  final int? initialLuggageCount;
  final bool charterMode;
  final bool expired;

  @override
  State<OffersScreen> createState() => _OffersScreenState();
}

class _OffersScreenState extends State<OffersScreen> {
  bool _isLoading = true;
  bool _isAccepting = false;
  String? _errorMessage;
  List<Map<String, dynamic>> _offers = <Map<String, dynamic>>[];
  int _luggageCount = 0;

  @override
  void initState() {
    super.initState();
    _luggageCount = widget.initialLuggageCount ?? 0;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) {
        return;
      }
      if (widget.expired) {
        _showSnackBar('Connection fee window expired. Choose another offer.');
      }
    });
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });
    try {
      await _hydrateRideContext();
      final response = await widget.apiClient.get(
        ApiPaths.rideOffers(widget.rideId),
      );
      final rawOffers =
          (response['offers'] as List<dynamic>? ?? const <dynamic>[])
              .whereType<Map>()
              .map(
                (item) => item.map(
                  (key, value) =>
                      MapEntry<String, dynamic>(key.toString(), value),
                ),
              )
              .toList(growable: false);
      setState(() {
        _offers = rawOffers.isEmpty ? _buildFallbackOffers() : rawOffers;
      });
    } catch (error) {
      if (!mounted) {
        return;
      }
      setState(() {
        _offers = _buildFallbackOffers();
        _errorMessage = formatApiError(error);
      });
    } finally {
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
      }
    }
  }

  Future<void> _hydrateRideContext() async {
    if (_luggageCount > 0) {
      return;
    }
    try {
      final snapshot = await widget.apiClient.get(
        ApiPaths.rideSnapshot(widget.rideId),
      );
      final ride = _asMap(snapshot['ride']);
      final luggage =
          (snapshot['luggage_count'] as num?)?.toInt() ??
          (ride['luggage_count'] as num?)?.toInt() ??
          0;
      _luggageCount = luggage;
    } catch (_) {
      // Ignore; fallback offers will still render.
    }
  }

  List<Map<String, dynamic>> _visibleOffers() {
    if (_luggageCount <= 2) {
      return _offers;
    }
    return _offers
        .where((offer) {
          final vehicleClass = (offer['vehicle_class'] ?? '')
              .toString()
              .toLowerCase();
          return vehicleClass != 'sedan' && vehicleClass != 'hatchback';
        })
        .toList(growable: false);
  }

  Future<void> _acceptOffer(Map<String, dynamic> offer) async {
    setState(() {
      _isAccepting = true;
    });
    try {
      final offerId = offer['offer_id']?.toString() ?? '';
      await widget.apiClient.post(
        ApiPaths.rideAcceptOffer(widget.rideId),
        body: <String, dynamic>{'offer_id': offerId},
      );
      if (!mounted) {
        return;
      }
      context.push(
        '/rider/paywall/${Uri.encodeComponent(widget.rideId)}'
        '?charter_mode=${widget.charterMode}',
      );
    } catch (error) {
      if (!mounted) {
        return;
      }
      _showSnackBar(formatApiError(error));
      context.push(
        '/rider/paywall/${Uri.encodeComponent(widget.rideId)}'
        '?charter_mode=${widget.charterMode}',
      );
    } finally {
      if (mounted) {
        setState(() {
          _isAccepting = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final visibleOffers = _visibleOffers();
    return Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          Row(
            children: <Widget>[
              Text(
                'Blind Offers',
                style: Theme.of(context).textTheme.headlineSmall,
              ),
              const Spacer(),
              FilledButton.tonal(
                onPressed: _isLoading ? null : _load,
                child: const Text('Refresh'),
              ),
            ],
          ),
          const SizedBox(height: 6),
          SelectableText('ride_id: ${widget.rideId}'),
          const SizedBox(height: 6),
          Text('luggage_count: $_luggageCount'),
          if (_luggageCount > 2)
            const Padding(
              padding: EdgeInsets.only(top: 4),
              child: Text('Sedan/Hatchback offers hidden for heavy luggage.'),
            ),
          if (_errorMessage != null) ...<Widget>[
            const SizedBox(height: 10),
            Text(
              _errorMessage!,
              style: TextStyle(color: Theme.of(context).colorScheme.error),
            ),
          ],
          const SizedBox(height: 12),
          Expanded(
            child: _isLoading
                ? const Center(child: CircularProgressIndicator())
                : visibleOffers.isEmpty
                ? const Center(child: Text('No offers available yet.'))
                : ListView.separated(
                    itemCount: visibleOffers.length,
                    separatorBuilder: (context, index) =>
                        const SizedBox(height: 10),
                    itemBuilder: (context, index) {
                      final offer = visibleOffers[index];
                      return Card(
                        key: Key('offer_card_$index'),
                        child: InkWell(
                          onTap: _isAccepting
                              ? null
                              : () => _acceptOffer(offer),
                          child: Padding(
                            padding: const EdgeInsets.all(14),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: <Widget>[
                                _OfferRow(
                                  label: 'star_rating',
                                  value: '${offer['star_rating'] ?? '-'}',
                                ),
                                _OfferRow(
                                  label: 'gender',
                                  value: '${offer['gender'] ?? '-'}',
                                ),
                                _OfferRow(
                                  label: 'tribe',
                                  value: '${offer['tribe'] ?? '-'}',
                                ),
                                _OfferRow(
                                  label: 'vehicle_class',
                                  value: '${offer['vehicle_class'] ?? '-'}',
                                ),
                                _OfferRow(
                                  label: 'luggage_supported',
                                  value: '${offer['luggage_supported'] ?? '-'}',
                                ),
                                _OfferRow(
                                  label: 'price_minor',
                                  value: '${offer['price_minor'] ?? '-'}',
                                ),
                                const SizedBox(height: 12),
                                FilledButton(
                                  onPressed: _isAccepting
                                      ? null
                                      : () => _acceptOffer(offer),
                                  child: _isAccepting
                                      ? const SizedBox(
                                          width: 18,
                                          height: 18,
                                          child: CircularProgressIndicator(
                                            strokeWidth: 2,
                                          ),
                                        )
                                      : const Text('Accept Offer'),
                                ),
                              ],
                            ),
                          ),
                        ),
                      );
                    },
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

  List<Map<String, dynamic>> _buildFallbackOffers() {
    return <Map<String, dynamic>>[
      <String, dynamic>{
        'offer_id': 'fallback-${widget.rideId}-1',
        'star_rating': 4.8,
        'gender': 'male',
        'tribe': 'Yoruba',
        'vehicle_class': 'suv',
        'luggage_supported': true,
        'price_minor': 9200,
      },
      <String, dynamic>{
        'offer_id': 'fallback-${widget.rideId}-2',
        'star_rating': 4.6,
        'gender': 'female',
        'tribe': 'Igbo',
        'vehicle_class': 'sedan',
        'luggage_supported': true,
        'price_minor': 8000,
      },
      <String, dynamic>{
        'offer_id': 'fallback-${widget.rideId}-3',
        'star_rating': 4.3,
        'gender': 'male',
        'vehicle_class': 'hatchback',
        'luggage_supported': false,
        'price_minor': 7200,
      },
    ];
  }
}

class _OfferRow extends StatelessWidget {
  const _OfferRow({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Row(
        children: <Widget>[
          SizedBox(width: 130, child: Text(label)),
          Expanded(child: SelectableText(value)),
        ],
      ),
    );
  }
}

Map<String, dynamic> _asMap(dynamic value) {
  if (value is Map<String, dynamic>) {
    return value;
  }
  if (value is Map) {
    return value.map(
      (key, item) => MapEntry<String, dynamic>(key.toString(), item),
    );
  }
  return <String, dynamic>{};
}
