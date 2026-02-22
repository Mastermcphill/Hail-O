class RouteNode {
  const RouteNode({
    required this.id,
    required this.routeId,
    required this.sequenceNo,
    required this.label,
    required this.createdAt,
    this.latitude,
    this.longitude,
  });

  final String id;
  final String routeId;
  final int sequenceNo;
  final String label;
  final double? latitude;
  final double? longitude;
  final DateTime createdAt;

  Map<String, Object?> toMap() {
    return <String, Object?>{
      'id': id,
      'route_id': routeId,
      'sequence_no': sequenceNo,
      'label': label,
      'latitude': latitude,
      'longitude': longitude,
      'created_at': createdAt.toUtc().toIso8601String(),
    };
  }

  factory RouteNode.fromMap(Map<String, Object?> map) {
    return RouteNode(
      id: map['id'] as String,
      routeId: map['route_id'] as String,
      sequenceNo: (map['sequence_no'] as num?)?.toInt() ?? 0,
      label: map['label'] as String,
      latitude: (map['latitude'] as num?)?.toDouble(),
      longitude: (map['longitude'] as num?)?.toDouble(),
      createdAt: DateTime.parse(map['created_at'] as String).toUtc(),
    );
  }
}
