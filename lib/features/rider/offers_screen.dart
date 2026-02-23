import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../core/api/api_client.dart';
import '../../core/api/api_errors.dart';
import '../../core/api/api_paths.dart';
import '../../core/api/mock_backend_store.dart';

class OffersScreen extends StatefulWidget {
  const OffersScreen({
    super.key,
    required this.apiClient,
    required this.rideId,
    required this.luggageCount,
    required this.charterMode,
  });

  final ApiClient apiClient;
  final String rideId;
  final int luggageCount;
  final bool charterMode;

  @override
  State<OffersScreen> createState() => _OffersScreenState();
}

class _OffersScreenState extends State<OffersScreen> {
  List<Map<String, dynamic>> _offers = <Map<String, dynamic>>[];
  bool _isLoading = true;
  String? _errorMessage;
  String? _acceptingOfferId;

  @override
  void initState() {
    super.initState();
    _loadOffers();
  }

  Future<void> _loadOffers() async {
    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });
    try {
      final response = await widget.apiClient.get(
        ApiPaths.rideOffers(widget.rideId),
      );
      final offers = _extractOffers(response);
      setState(() {
        _offers = offers.isEmpty ? _mockOffers(widget.rideId) : offers;
      });
    } catch (error) {
      if (error is ApiException && error.statusCode == 404) {
        setState(() {
          _offers = _mockOffers(widget.rideId);
        });
      } else {
        setState(() {
          _errorMessage = formatApiError(error);
          _offers = _mockOffers(widget.rideId);
        });
      }
    } finally {
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
      }
    }
  }

  Future<void> _acceptOffer(Map<String, dynamic> offer) async {
    final offerId = _readString(offer['offer_id']);
    if (offerId.isEmpty) {
      _showSnackBar('Offer id is missing.');
      return;
    }

    setState(() {
      _acceptingOfferId = offerId;
    });

    try {
      await widget.apiClient.post(
        ApiPaths.rideAcceptOffer(widget.rideId),
        body: <String, dynamic>{'offer_id': offerId},
      );
    } catch (error) {
      if (error is! ApiException || error.statusCode != 404) {
        if (!mounted) {
          return;
        }
        _showSnackBar(formatApiError(error));
        setState(() {
          _acceptingOfferId = null;
        });
        return;
      }
      MockBackendStore.acceptedOfferByRideId[widget.rideId] = offer;
    }

    MockBackendStore.acceptedOfferByRideId[widget.rideId] = offer;

    if (!mounted) {
      return;
    }
    setState(() {
      _acceptingOfferId = null;
    });
    final offerPrice = _readInt(offer['price_minor']);
    final charterFlag = widget.charterMode ? '1' : '0';
    context.push(
      '/rider/paywall/${Uri.encodeComponent(widget.rideId)}'
      '?offerPrice=$offerPrice'
      '&charter=$charterFlag'
      '&luggage=${widget.luggageCount}',
    );
  }

  @override
  Widget build(BuildContext context) {
    final filteredOffers = _applyLuggageFilter(_offers, widget.luggageCount);
    return Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          Text(
            'Blind Offers',
            style: Theme.of(context).textTheme.headlineSmall,
          ),
          const SizedBox(height: 4),
          SelectableText('ride_id: ${widget.rideId}'),
          const SizedBox(height: 4),
          Text('luggage_count: ${widget.luggageCount}'),
          if (_errorMessage != null) ...<Widget>[
            const SizedBox(height: 8),
            Text(
              _errorMessage!,
              style: TextStyle(color: Theme.of(context).colorScheme.error),
            ),
          ],
          const SizedBox(height: 12),
          Row(
            children: <Widget>[
              FilledButton.tonal(
                onPressed: _isLoading ? null : _loadOffers,
                child: const Text('Refresh offers'),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Expanded(
            child: _isLoading
                ? const Center(child: CircularProgressIndicator())
                : filteredOffers.isEmpty
                ? const Center(
                    child: Text(
                      'No offers available for current luggage filter.',
                    ),
                  )
                : ListView.separated(
                    itemCount: filteredOffers.length,
                    separatorBuilder: (_, index) => const SizedBox(height: 10),
                    itemBuilder: (context, index) {
                      final offer = filteredOffers[index];
                      final offerId = _readString(offer['offer_id']);
                      final isAccepting = _acceptingOfferId == offerId;
                      return Card(
                        child: InkWell(
                          key: Key('offer_card_$index'),
                          borderRadius: BorderRadius.circular(12),
                          onTap: isAccepting ? null : () => _acceptOffer(offer),
                          child: Padding(
                            padding: const EdgeInsets.all(12),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: <Widget>[
                                _OfferRow(
                                  label: 'star_rating',
                                  value: _readStringOrDash(
                                    offer['star_rating'],
                                  ),
                                ),
                                _OfferRow(
                                  label: 'gender',
                                  value: _readStringOrDash(offer['gender']),
                                ),
                                _OfferRow(
                                  label: 'tribe',
                                  value: _readStringOrDash(offer['tribe']),
                                ),
                                _OfferRow(
                                  label: 'vehicle_class',
                                  value: _readStringOrDash(
                                    offer['vehicle_class'],
                                  ),
                                ),
                                _OfferRow(
                                  label: 'luggage_supported',
                                  value: _readBool(offer['luggage_supported'])
                                      ? 'true'
                                      : 'false',
                                ),
                                _OfferRow(
                                  label: 'price_minor',
                                  value: _readInt(
                                    offer['price_minor'],
                                  ).toString(),
                                ),
                                const SizedBox(height: 8),
                                Align(
                                  alignment: Alignment.centerRight,
                                  child: FilledButton(
                                    key: Key('offer_accept_button_$index'),
                                    onPressed: isAccepting
                                        ? null
                                        : () => _acceptOffer(offer),
                                    child: isAccepting
                                        ? const SizedBox(
                                            width: 16,
                                            height: 16,
                                            child: CircularProgressIndicator(
                                              strokeWidth: 2,
                                            ),
                                          )
                                        : const Text('Accept offer'),
                                  ),
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
}

class _OfferRow extends StatelessWidget {
  const _OfferRow({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 4),
      child: Row(
        children: <Widget>[
          SizedBox(width: 130, child: Text(label)),
          Expanded(child: SelectableText(value)),
        ],
      ),
    );
  }
}

List<Map<String, dynamic>> _extractOffers(Map<String, dynamic> response) {
  final directList = response['offers'];
  if (directList is List) {
    return _normalizeList(directList);
  }
  final nestedData = response['data'];
  if (nestedData is List) {
    return _normalizeList(nestedData);
  }
  if (nestedData is Map) {
    final nestedOffers = nestedData['offers'];
    if (nestedOffers is List) {
      return _normalizeList(nestedOffers);
    }
  }
  return <Map<String, dynamic>>[];
}

List<Map<String, dynamic>> _normalizeList(List<dynamic> source) {
  return source
      .whereType<Map>()
      .map(
        (item) => item.map(
          (key, value) => MapEntry<String, dynamic>(key.toString(), value),
        ),
      )
      .toList(growable: false);
}

List<Map<String, dynamic>> _mockOffers(String rideId) {
  final stored = MockBackendStore.offersByRideId[rideId];
  if (stored != null && stored.isNotEmpty) {
    return stored;
  }
  return <Map<String, dynamic>>[
    <String, dynamic>{
      'offer_id': 'mock_offer_1',
      'star_rating': 4.8,
      'gender': 'male',
      'tribe': 'yoruba',
      'vehicle_class': 'sedan',
      'luggage_supported': true,
      'price_minor': 4200,
    },
    <String, dynamic>{
      'offer_id': 'mock_offer_2',
      'star_rating': 4.5,
      'gender': 'female',
      'tribe': 'igbo',
      'vehicle_class': 'suv',
      'luggage_supported': true,
      'price_minor': 5600,
    },
    <String, dynamic>{
      'offer_id': 'mock_offer_3',
      'star_rating': 4.9,
      'gender': 'male',
      'tribe': 'hausa',
      'vehicle_class': 'hatchback',
      'luggage_supported': false,
      'price_minor': 3900,
    },
  ];
}

List<Map<String, dynamic>> _applyLuggageFilter(
  List<Map<String, dynamic>> offers,
  int luggageCount,
) {
  if (luggageCount <= 2) {
    return offers;
  }
  return offers
      .where((offer) {
        final vehicleClass = _readString(offer['vehicle_class']).toLowerCase();
        return vehicleClass != 'sedan' && vehicleClass != 'hatchback';
      })
      .toList(growable: false);
}

String _readString(Object? value) {
  if (value is String) {
    return value.trim();
  }
  return '';
}

String _readStringOrDash(Object? value) {
  final text = _readString(value);
  if (text.isNotEmpty) {
    return text;
  }
  if (value != null) {
    return value.toString();
  }
  return '-';
}

int _readInt(Object? value) {
  if (value is int) {
    return value;
  }
  if (value is num) {
    return value.toInt();
  }
  if (value is String) {
    return int.tryParse(value.trim()) ?? 0;
  }
  return 0;
}

bool _readBool(Object? value) {
  if (value is bool) {
    return value;
  }
  if (value is String) {
    return value.toLowerCase() == 'true';
  }
  return false;
}
