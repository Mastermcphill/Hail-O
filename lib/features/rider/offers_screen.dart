import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../core/api/api_client.dart';
import '../../core/api/api_errors.dart';
import '../../core/api/api_paths.dart';
import '../../features/rideshare/models/ride_search_draft.dart';
import '../../theme/app_tokens.dart';
import '../../widgets/premium_ui.dart';
import '../../widgets/ride_result_card.dart';
import '../../widgets/trust_badge.dart';

class OffersScreen extends StatefulWidget {
  const OffersScreen({
    super.key,
    required this.apiClient,
    required this.rideId,
    int? initialLuggageCount,
    int? luggageCount,
    this.charterMode = false,
    this.expired = false,
    this.draftEncoded,
  }) : initialLuggageCount = initialLuggageCount ?? luggageCount;

  final ApiClient apiClient;
  final String rideId;
  final int? initialLuggageCount;
  final bool charterMode;
  final bool expired;
  final String? draftEncoded;

  @override
  State<OffersScreen> createState() => _OffersScreenState();
}

class _OffersScreenState extends State<OffersScreen> {
  bool _isLoading = true;
  bool _isAccepting = false;
  String? _errorMessage;
  List<Map<String, dynamic>> _offers = <Map<String, dynamic>>[];
  int _luggageCount = 0;

  late final RideSearchDraft _draft;

  @override
  void initState() {
    super.initState();
    _draft = RideSearchDraft.fromEncoded(widget.draftEncoded);
    _luggageCount = widget.initialLuggageCount ?? 0;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) {
        return;
      }
      if (widget.expired) {
        _showSnackBar('Connection fee window expired. Choose another ride.');
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
        _offers = rawOffers;
      });
    } catch (error) {
      if (!mounted) {
        return;
      }
      setState(() {
        _offers = const <Map<String, dynamic>>[];
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
      _luggageCount =
          (snapshot['luggage_count'] as num?)?.toInt() ??
          (ride['luggage_count'] as num?)?.toInt() ??
          0;
    } catch (_) {
      // Ignore. Offers can still render without luggage context.
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
      final priceMinor = (offer['price_minor'] as num?)?.toInt();
      context.push(
        '/rider/paywall/${Uri.encodeComponent(widget.rideId)}'
        '?charter_mode=${widget.charterMode}'
        '&draft=${Uri.encodeQueryComponent(_draft.toEncoded())}'
        '${priceMinor == null ? '' : '&offer_price_minor=$priceMinor'}'
        '&luggage_count=$_luggageCount',
      );
    } catch (error) {
      if (!mounted) {
        return;
      }
      _showSnackBar(formatApiError(error));
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
    return SingleChildScrollView(
      padding: const EdgeInsets.all(HailoSpacing.lg),
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 1080),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: <Widget>[
              PremiumPanel(
                gradient: context.hailoTokens.heroGradient,
                borderColor: Colors.white.withValues(alpha: 0.10),
                child: Wrap(
                  spacing: HailoSpacing.xl,
                  runSpacing: HailoSpacing.lg,
                  children: <Widget>[
                    ConstrainedBox(
                      constraints: const BoxConstraints(maxWidth: 560),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: <Widget>[
                          const PremiumPill(
                            label: 'Ride matches',
                            icon: Icons.route_rounded,
                            backgroundColor: Color(0x24FFFFFF),
                            foregroundColor: Colors.white,
                          ),
                          const SizedBox(height: HailoSpacing.lg),
                          Text(
                            'Choose the ride that fits your route, comfort level, and timing.',
                            style: Theme.of(context).textTheme.headlineMedium
                                ?.copyWith(
                                  color: Colors.white,
                                  fontWeight: FontWeight.w800,
                                ),
                          ),
                          const SizedBox(height: HailoSpacing.md),
                          Text(
                            'Fares, operator quality, comfort, and seat posture are arranged to help you convert quickly without hunting through raw data.',
                            style: Theme.of(context).textTheme.bodyLarge
                                ?.copyWith(
                                  color: Colors.white.withValues(alpha: 0.88),
                                ),
                          ),
                        ],
                      ),
                    ),
                    ConstrainedBox(
                      constraints: const BoxConstraints(maxWidth: 320),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: const <Widget>[
                          Text(
                            'Filters',
                            style: TextStyle(
                              color: Colors.white,
                              fontSize: 18,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                          SizedBox(height: HailoSpacing.md),
                          Wrap(
                            spacing: HailoSpacing.xs,
                            runSpacing: HailoSpacing.xs,
                            children: <Widget>[
                              PremiumPill(
                                label: 'Fastest',
                                icon: Icons.bolt_rounded,
                                backgroundColor: Color(0x24FFFFFF),
                                foregroundColor: Colors.white,
                              ),
                              PremiumPill(
                                label: 'Affordable',
                                icon: Icons.savings_outlined,
                                backgroundColor: Color(0x24FFFFFF),
                                foregroundColor: Colors.white,
                              ),
                              PremiumPill(
                                label: 'Most comfortable',
                                icon:
                                    Icons.airline_seat_recline_normal_outlined,
                                backgroundColor: Color(0x24FFFFFF),
                                foregroundColor: Colors.white,
                              ),
                              PremiumPill(
                                label: 'Premium',
                                icon: Icons.workspace_premium_outlined,
                                backgroundColor: Color(0x24FFFFFF),
                                foregroundColor: Colors.white,
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: HailoSpacing.section),
              if (_errorMessage != null) ...<Widget>[
                Text(
                  _errorMessage!,
                  style: TextStyle(color: Theme.of(context).colorScheme.error),
                ),
                const SizedBox(height: HailoSpacing.md),
              ],
              if (_isLoading)
                const Padding(
                  padding: EdgeInsets.symmetric(vertical: HailoSpacing.section),
                  child: Center(child: CircularProgressIndicator()),
                )
              else if (visibleOffers.isEmpty)
                PremiumPanel(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: const <Widget>[
                      PremiumSectionHeader(
                        eyebrow: 'No matches yet',
                        title: 'We are still searching the network.',
                        description:
                            'Try adjusting your travel mode, seat tier, or departure time if no live rides are available yet.',
                      ),
                    ],
                  ),
                )
              else
                for (
                  var index = 0;
                  index < visibleOffers.length;
                  index++
                ) ...<Widget>[
                  _buildOfferCard(context, visibleOffers[index], index),
                  const SizedBox(height: HailoSpacing.md),
                ],
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildOfferCard(
    BuildContext context,
    Map<String, dynamic> offer,
    int index,
  ) {
    final priceMinor = (offer['price_minor'] as num?)?.toInt() ?? 0;
    final rating = (offer['star_rating'] as num?)?.toDouble() ?? 4.7;
    final vehicleClass = (offer['vehicle_class'] ?? 'ride').toString();
    final schedule = _formatSchedule(
      offer['accepted_at']?.toString(),
      fallback: _draft.departureAt,
    );
    final category = _categoryForOffer(
      vehicleClass,
      _draft.seatTier,
      widget.charterMode,
    );
    final operatorName = _operatorLabel(offer['driver_id']?.toString());
    final seatAvailability = _seatAvailabilityLabel(vehicleClass);
    final tags = _tagsForOffer(index, vehicleClass);
    final trustBadges = <TrustBadge>[
      TrustBadge(
        label: 'Rated ${rating.toStringAsFixed(1)}',
        icon: Icons.star_rounded,
      ),
      if (offer['luggage_supported'] == true)
        const TrustBadge(
          label: 'Luggage friendly',
          icon: Icons.luggage_rounded,
        ),
      const TrustBadge(label: 'Operator on file', icon: Icons.badge_outlined),
    ];

    return RideResultCard(
      category: category,
      operatorName: operatorName,
      scheduleLabel: schedule,
      priceLabel: _money(priceMinor),
      ratingLabel: rating.toStringAsFixed(1),
      seatAvailabilityLabel: seatAvailability,
      tags: tags,
      trustBadges: trustBadges,
      heroNote:
          'Escrow payment protection stays active through checkout and seat confirmation.',
      primaryLabel: _isAccepting ? 'Selecting...' : 'Select ride',
      secondaryLabel: 'View details',
      onPrimaryPressed: _isAccepting ? () {} : () => _acceptOffer(offer),
      onSecondaryPressed: () => _showSnackBar(
        '$category | ${seatAvailability.toLowerCase()} | ${_money(priceMinor)}',
      ),
    );
  }

  void _showSnackBar(String message) {
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(message)));
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

String _categoryForOffer(
  String vehicleClass,
  RideSeatTier seatTier,
  bool charterMode,
) {
  if (charterMode) {
    return 'Fleet Coach';
  }
  final normalizedVehicle = vehicleClass.toLowerCase();
  if (normalizedVehicle.contains('executive')) {
    return 'Executive Ride';
  }
  if (normalizedVehicle.contains('premium')) {
    return 'Premium Ride';
  }
  if (normalizedVehicle.contains('comfort') ||
      normalizedVehicle.contains('suv')) {
    return 'Comfort Ride';
  }
  switch (seatTier) {
    case RideSeatTier.executive:
      return 'Executive Ride';
    case RideSeatTier.premium:
      return 'Premium Ride';
    case RideSeatTier.comfort:
      return 'Comfort Ride';
    case RideSeatTier.standard:
      return 'Standard Ride';
  }
}

String _operatorLabel(String? driverId) {
  final raw = (driverId ?? '').trim();
  if (raw.isEmpty) {
    return 'Verified mobility operator';
  }
  final end = raw.length < 6 ? raw.length : 6;
  return 'Driver ${raw.substring(0, end)}';
}

String _seatAvailabilityLabel(String vehicleClass) {
  final normalized = vehicleClass.toLowerCase();
  if (normalized.contains('coach') || normalized.contains('van')) {
    return '8+ seats left';
  }
  if (normalized.contains('suv')) {
    return '4 seats left';
  }
  return '3 seats left';
}

List<String> _tagsForOffer(int index, String vehicleClass) {
  if (index == 0) {
    return const <String>['Fastest'];
  }
  if (index == 1) {
    return const <String>['Most affordable'];
  }
  if (vehicleClass.toLowerCase().contains('premium') ||
      vehicleClass.toLowerCase().contains('executive')) {
    return const <String>['Premium option'];
  }
  return const <String>['Most comfortable'];
}

String _formatSchedule(String? isoValue, {required DateTime fallback}) {
  final parsed =
      DateTime.tryParse((isoValue ?? '').trim())?.toLocal() ??
      fallback.toLocal();
  return DateFormat('EEE, h:mm a').format(parsed);
}

String _money(int amountMinor) {
  return '\$${(amountMinor / 100).toStringAsFixed(2)}';
}
