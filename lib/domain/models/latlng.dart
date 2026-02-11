class LatLng {
  const LatLng({required this.latitude, required this.longitude});

  final double latitude;
  final double longitude;

  Map<String, double> toMap() {
    return <String, double>{'lat': latitude, 'lng': longitude};
  }

  List<double> toJsonPair() => <double>[latitude, longitude];

  factory LatLng.fromMap(Map<String, Object?> map) {
    return LatLng(
      latitude: (map['lat'] as num?)?.toDouble() ?? 0,
      longitude: (map['lng'] as num?)?.toDouble() ?? 0,
    );
  }

  factory LatLng.fromJsonPair(List<Object?> pair) {
    return LatLng(
      latitude: (pair.first as num?)?.toDouble() ?? 0,
      longitude: (pair.last as num?)?.toDouble() ?? 0,
    );
  }
}
