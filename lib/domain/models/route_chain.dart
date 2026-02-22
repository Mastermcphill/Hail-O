import 'route_node.dart';

class RouteChain {
  const RouteChain({
    required this.id,
    required this.driverId,
    required this.origin,
    required this.destination,
    required this.totalDistanceKm,
    required this.status,
    required this.createdAt,
    required this.updatedAt,
    this.polyline,
    this.nodes = const <RouteNode>[],
  });

  final String id;
  final String driverId;
  final String origin;
  final String destination;
  final String? polyline;
  final double totalDistanceKm;
  final String status;
  final DateTime createdAt;
  final DateTime updatedAt;
  final List<RouteNode> nodes;

  Map<String, Object?> toMap() {
    return <String, Object?>{
      'id': id,
      'driver_id': driverId,
      'origin': origin,
      'destination': destination,
      'polyline': polyline,
      'total_distance_km': totalDistanceKm,
      'status': status,
      'created_at': createdAt.toUtc().toIso8601String(),
      'updated_at': updatedAt.toUtc().toIso8601String(),
    };
  }

  factory RouteChain.fromMap(
    Map<String, Object?> map, {
    List<RouteNode> nodes = const <RouteNode>[],
  }) {
    return RouteChain(
      id: map['id'] as String,
      driverId: map['driver_id'] as String,
      origin: map['origin'] as String,
      destination: map['destination'] as String,
      polyline: map['polyline'] as String?,
      totalDistanceKm: (map['total_distance_km'] as num?)?.toDouble() ?? 0,
      status: map['status'] as String? ?? 'active',
      createdAt: DateTime.parse(map['created_at'] as String).toUtc(),
      updatedAt: DateTime.parse(map['updated_at'] as String).toUtc(),
      nodes: nodes,
    );
  }
}
