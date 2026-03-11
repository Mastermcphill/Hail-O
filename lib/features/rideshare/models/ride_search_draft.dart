import 'dart:convert';

enum RideTravelMode { city, interCity, interState, crossBorder }

enum RideSeatTier { standard, comfort, premium, executive }

class RideSearchDraft {
  const RideSearchDraft({
    required this.pickup,
    required this.destination,
    required this.departureAt,
    required this.passengerCount,
    required this.travelMode,
    required this.seatTier,
    this.luggageCount = 0,
    this.charterMode = false,
  });

  final String pickup;
  final String destination;
  final DateTime departureAt;
  final int passengerCount;
  final RideTravelMode travelMode;
  final RideSeatTier seatTier;
  final int luggageCount;
  final bool charterMode;

  factory RideSearchDraft.initial() {
    return RideSearchDraft(
      pickup: '',
      destination: '',
      departureAt: DateTime.now().toUtc().add(const Duration(minutes: 30)),
      passengerCount: 1,
      travelMode: RideTravelMode.city,
      seatTier: RideSeatTier.standard,
    );
  }

  factory RideSearchDraft.fromJson(Map<String, dynamic> json) {
    return RideSearchDraft(
      pickup: (json['pickup'] as String? ?? '').trim(),
      destination: (json['destination'] as String? ?? '').trim(),
      departureAt:
          DateTime.tryParse(json['departure_at'] as String? ?? '')?.toUtc() ??
          DateTime.now().toUtc().add(const Duration(minutes: 30)),
      passengerCount: _readInt(json['passenger_count'], fallback: 1),
      travelMode: rideTravelModeFromKey(
        (json['travel_mode'] as String? ?? '').trim(),
      ),
      seatTier: rideSeatTierFromKey(
        (json['seat_tier'] as String? ?? '').trim(),
      ),
      luggageCount: _readInt(json['luggage_count']),
      charterMode: json['charter_mode'] == true,
    );
  }

  factory RideSearchDraft.fromEncoded(String? encoded) {
    final raw = (encoded ?? '').trim();
    if (raw.isEmpty) {
      return RideSearchDraft.initial();
    }
    try {
      final normalized = base64Url.normalize(raw);
      final decoded = utf8.decode(base64Url.decode(normalized));
      final json = jsonDecode(decoded);
      if (json is Map<String, dynamic>) {
        return RideSearchDraft.fromJson(json);
      }
      if (json is Map) {
        return RideSearchDraft.fromJson(
          json.map(
            (key, value) => MapEntry<String, dynamic>(key.toString(), value),
          ),
        );
      }
    } catch (_) {
      // Invalid query payloads fall back to a safe draft.
    }
    return RideSearchDraft.initial();
  }

  RideSearchDraft copyWith({
    String? pickup,
    String? destination,
    DateTime? departureAt,
    int? passengerCount,
    RideTravelMode? travelMode,
    RideSeatTier? seatTier,
    int? luggageCount,
    bool? charterMode,
  }) {
    return RideSearchDraft(
      pickup: pickup ?? this.pickup,
      destination: destination ?? this.destination,
      departureAt: departureAt ?? this.departureAt,
      passengerCount: passengerCount ?? this.passengerCount,
      travelMode: travelMode ?? this.travelMode,
      seatTier: seatTier ?? this.seatTier,
      luggageCount: luggageCount ?? this.luggageCount,
      charterMode: charterMode ?? this.charterMode,
    );
  }

  Map<String, dynamic> toJson() {
    return <String, dynamic>{
      'pickup': pickup,
      'destination': destination,
      'departure_at': departureAt.toUtc().toIso8601String(),
      'passenger_count': passengerCount,
      'travel_mode': travelMode.key,
      'seat_tier': seatTier.key,
      'luggage_count': luggageCount,
      'charter_mode': charterMode,
    };
  }

  String toEncoded() {
    return base64UrlEncode(utf8.encode(jsonEncode(toJson())));
  }

  String get backendTripScope {
    switch (travelMode) {
      case RideTravelMode.city:
        return 'intra_city';
      case RideTravelMode.interCity:
      case RideTravelMode.interState:
        return 'inter_state';
      case RideTravelMode.crossBorder:
        return 'international';
    }
  }

  String get vehicleClassPreset {
    switch (seatTier) {
      case RideSeatTier.standard:
        return travelMode == RideTravelMode.city ? 'sedan' : 'coach';
      case RideSeatTier.comfort:
        return travelMode == RideTravelMode.city ? 'suv' : 'comfort_van';
      case RideSeatTier.premium:
        return travelMode == RideTravelMode.city
            ? 'premium_suv'
            : 'premium_van';
      case RideSeatTier.executive:
        return travelMode == RideTravelMode.city
            ? 'executive_suv'
            : 'executive_van';
    }
  }

  int get baseFareMinor {
    switch (travelMode) {
      case RideTravelMode.city:
        return 6200;
      case RideTravelMode.interCity:
        return 9800;
      case RideTravelMode.interState:
        return 14800;
      case RideTravelMode.crossBorder:
        return 23500;
    }
  }

  int get premiumMarkupMinor {
    switch (seatTier) {
      case RideSeatTier.standard:
        return 0;
      case RideSeatTier.comfort:
        return 1800;
      case RideSeatTier.premium:
        return 4200;
      case RideSeatTier.executive:
        return 7600;
    }
  }

  int get connectionFeeMinor {
    switch (travelMode) {
      case RideTravelMode.city:
        return 1200;
      case RideTravelMode.interCity:
        return 1800;
      case RideTravelMode.interState:
        return 2400;
      case RideTravelMode.crossBorder:
        return 3000;
    }
  }

  String get travelModeLabel {
    switch (travelMode) {
      case RideTravelMode.city:
        return 'City rides';
      case RideTravelMode.interCity:
        return 'Inter-city';
      case RideTravelMode.interState:
        return 'Inter-state';
      case RideTravelMode.crossBorder:
        return 'Cross-border';
    }
  }

  String get seatTierLabel {
    switch (seatTier) {
      case RideSeatTier.standard:
        return 'Standard';
      case RideSeatTier.comfort:
        return 'Comfort';
      case RideSeatTier.premium:
        return 'Premium';
      case RideSeatTier.executive:
        return 'Executive';
    }
  }

  String get seatTierDescriptor {
    switch (seatTier) {
      case RideSeatTier.standard:
        return 'Balanced everyday seat';
      case RideSeatTier.comfort:
        return 'Extra room and smoother ride';
      case RideSeatTier.premium:
        return 'Quieter cabin and priority comfort';
      case RideSeatTier.executive:
        return 'Front-tier executive experience';
    }
  }

  String get bookingSummaryLabel => '$travelModeLabel • $seatTierLabel';

  bool get isCrossBorder => travelMode == RideTravelMode.crossBorder;
}

extension on RideTravelMode {
  String get key {
    switch (this) {
      case RideTravelMode.city:
        return 'city';
      case RideTravelMode.interCity:
        return 'inter_city';
      case RideTravelMode.interState:
        return 'inter_state';
      case RideTravelMode.crossBorder:
        return 'cross_border';
    }
  }
}

extension on RideSeatTier {
  String get key {
    switch (this) {
      case RideSeatTier.standard:
        return 'standard';
      case RideSeatTier.comfort:
        return 'comfort';
      case RideSeatTier.premium:
        return 'premium';
      case RideSeatTier.executive:
        return 'executive';
    }
  }
}

RideTravelMode rideTravelModeFromKey(String value) {
  switch (value.toLowerCase()) {
    case 'inter_city':
      return RideTravelMode.interCity;
    case 'inter_state':
      return RideTravelMode.interState;
    case 'cross_border':
    case 'international':
      return RideTravelMode.crossBorder;
    case 'city':
    default:
      return RideTravelMode.city;
  }
}

RideSeatTier rideSeatTierFromKey(String value) {
  switch (value.toLowerCase()) {
    case 'comfort':
      return RideSeatTier.comfort;
    case 'premium':
      return RideSeatTier.premium;
    case 'executive':
      return RideSeatTier.executive;
    case 'standard':
    default:
      return RideSeatTier.standard;
  }
}

int _readInt(Object? value, {int fallback = 0}) {
  if (value is int) {
    return value;
  }
  if (value is num) {
    return value.toInt();
  }
  if (value is String) {
    return int.tryParse(value.trim()) ?? fallback;
  }
  return fallback;
}
