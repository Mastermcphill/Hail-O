import 'dart:convert';

import 'ride_event_type.dart';

class RideEvent {
  const RideEvent({
    required this.id,
    required this.rideId,
    required this.eventType,
    required this.idempotencyScope,
    required this.idempotencyKey,
    required this.payloadJson,
    required this.createdAt,
    this.actorId,
  });

  final String id;
  final String rideId;
  final RideEventType eventType;
  final String? actorId;
  final String idempotencyScope;
  final String idempotencyKey;
  final String payloadJson;
  final DateTime createdAt;

  Map<String, Object?> toMap() {
    return <String, Object?>{
      'id': id,
      'ride_id': rideId,
      'event_type': eventType.dbValue,
      'actor_id': actorId,
      'idempotency_scope': idempotencyScope,
      'idempotency_key': idempotencyKey,
      'payload_json': payloadJson,
      'created_at': createdAt.toUtc().toIso8601String(),
    };
  }

  Map<String, Object?> payloadAsMap() {
    final decoded = jsonDecode(payloadJson);
    if (decoded is Map<String, Object?>) {
      return decoded;
    }
    if (decoded is Map) {
      return decoded.map((key, value) => MapEntry(key.toString(), value));
    }
    return const <String, Object?>{};
  }

  factory RideEvent.fromMap(Map<String, Object?> map) {
    return RideEvent(
      id: map['id'] as String,
      rideId: map['ride_id'] as String,
      eventType: RideEventType.fromDbValue(map['event_type'] as String),
      actorId: map['actor_id'] as String?,
      idempotencyScope: map['idempotency_scope'] as String,
      idempotencyKey: map['idempotency_key'] as String,
      payloadJson: (map['payload_json'] as String?) ?? '{}',
      createdAt: DateTime.parse(map['created_at'] as String).toUtc(),
    );
  }
}
