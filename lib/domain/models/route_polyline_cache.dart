import 'dart:convert';

import 'latlng.dart';

class RoutePolylineCache {
  const RoutePolylineCache({
    required this.routeId,
    required this.polyline,
    required this.totalDistanceM,
    required this.createdAt,
  });

  final String routeId;
  final List<LatLng> polyline;
  final double totalDistanceM;
  final DateTime createdAt;

  String get polylineJson => jsonEncode(
    polyline
        .map(
          (point) => <String, double>{
            'lat': point.latitude,
            'lng': point.longitude,
          },
        )
        .toList(growable: false),
  );

  Map<String, Object?> toMap() {
    return <String, Object?>{
      'route_id': routeId,
      'polyline_json': polylineJson,
      'total_distance_m': totalDistanceM,
      'created_at': createdAt.toUtc().toIso8601String(),
    };
  }

  factory RoutePolylineCache.fromMap(Map<String, Object?> map) {
    final rawJson = map['polyline_json'] as String? ?? '[]';
    final decoded = jsonDecode(rawJson) as List<dynamic>;
    final polyline = decoded
        .map((entry) => LatLng.fromMap(Map<String, Object?>.from(entry as Map)))
        .toList(growable: false);
    return RoutePolylineCache(
      routeId: map['route_id'] as String,
      polyline: polyline,
      totalDistanceM: (map['total_distance_m'] as num?)?.toDouble() ?? 0,
      createdAt: DateTime.parse(map['created_at'] as String).toUtc(),
    );
  }
}
