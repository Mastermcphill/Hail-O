class Offer {
  const Offer({
    required this.id,
    required this.title,
    required this.vehicleClass,
    required this.priceMinor,
    required this.rating,
    required this.seatsAvailable,
    required this.etaMinutes,
    required this.highlights,
  });

  final String id;
  final String title;
  final String vehicleClass;
  final int priceMinor;
  final double rating;
  final int seatsAvailable;
  final int etaMinutes;
  final List<String> highlights;

  factory Offer.fromMap(Map<String, dynamic> map) {
    return Offer(
      id: _readString(map['id']),
      title: _readString(map['title']),
      vehicleClass: _readString(map['vehicle_class']),
      priceMinor: _readInt(map['price_minor']),
      rating: _readDouble(map['rating']),
      seatsAvailable: _readInt(map['seats_available']),
      etaMinutes: _readInt(map['eta_minutes']),
      highlights: _readStringList(map['highlights']),
    );
  }

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
    };
  }
}

String _readString(Object? value) {
  if (value is String) {
    return value.trim();
  }
  return '';
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

double _readDouble(Object? value) {
  if (value is double) {
    return value;
  }
  if (value is num) {
    return value.toDouble();
  }
  if (value is String) {
    return double.tryParse(value.trim()) ?? 0;
  }
  return 0;
}

List<String> _readStringList(Object? value) {
  if (value is List) {
    return value.map((entry) => entry.toString()).toList(growable: false);
  }
  return <String>[];
}
