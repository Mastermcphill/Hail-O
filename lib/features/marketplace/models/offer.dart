class Offer {
  const Offer({
    required this.id,
    required this.title,
    this.vehicleClass = 'marketplace',
    int? priceMinor,
    int? price,
    this.rating = 0,
    this.seatsAvailable = 1,
    this.etaMinutes = 0,
    this.highlights = const <String>[],
    this.subtitle = '',
    this.currency = 'NGN',
    this.interval = 'trip',
    List<String>? perks,
  }) : priceMinor = priceMinor ?? price ?? 0,
       perks = perks ?? highlights;

  final String id;
  final String title;
  final String vehicleClass;
  final int priceMinor;
  final double rating;
  final int seatsAvailable;
  final int etaMinutes;
  final List<String> highlights;
  final String subtitle;
  final String currency;
  final String interval;
  final List<String> perks;

  // Compatibility for older UI/tests that still read `price`.
  int get price => priceMinor;

  factory Offer.fromMap(Map<String, dynamic> map) {
    final highlightSource = _stringList(
      map['highlights'],
      fallback: _stringList(map['perks']),
    );
    return Offer(
      id: _string(map['id']),
      title: _string(map['title']),
      vehicleClass: _string(map['vehicle_class'], fallback: 'marketplace'),
      priceMinor: _int(map['price_minor'], fallback: _int(map['price'])),
      rating: _double(map['rating']),
      seatsAvailable: _int(map['seats_available'], fallback: 1),
      etaMinutes: _int(map['eta_minutes']),
      highlights: highlightSource,
      subtitle: _string(map['subtitle']),
      currency: _string(map['currency'], fallback: 'NGN'),
      interval: _string(map['interval'], fallback: 'trip'),
      perks: _stringList(map['perks'], fallback: highlightSource),
    );
  }

  factory Offer.fromJson(Map<String, dynamic> json) => Offer.fromMap(json);

  Map<String, dynamic> toMap() {
    return <String, dynamic>{
      'id': id,
      'title': title,
      'vehicle_class': vehicleClass,
      'price_minor': priceMinor,
      'rating': rating,
      'seats_available': seatsAvailable,
      'eta_minutes': etaMinutes,
      'highlights': highlights,
      'subtitle': subtitle,
      'currency': currency,
      'interval': interval,
      'perks': perks,
    };
  }

  Map<String, dynamic> toJson() => toMap();
}

typedef MarketplaceOffer = Offer;

String _string(Object? value, {String fallback = ''}) {
  if (value is String) {
    final trimmed = value.trim();
    if (trimmed.isNotEmpty) {
      return trimmed;
    }
  }
  return fallback;
}

int _int(Object? value, {int fallback = 0}) {
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

double _double(Object? value, {double fallback = 0}) {
  if (value is double) {
    return value;
  }
  if (value is num) {
    return value.toDouble();
  }
  if (value is String) {
    return double.tryParse(value.trim()) ?? fallback;
  }
  return fallback;
}

List<String> _stringList(Object? value, {List<String>? fallback}) {
  if (value is List) {
    return value.map((item) => item.toString()).toList(growable: false);
  }
  return fallback ?? const <String>[];
}
