import 'dart:convert';

class DisputeEventRecord {
  const DisputeEventRecord({
    required this.id,
    required this.disputeId,
    required this.eventType,
    required this.actorId,
    required this.payloadJson,
    required this.idempotencyScope,
    required this.idempotencyKey,
    required this.createdAt,
  });

  final String id;
  final String disputeId;
  final String eventType;
  final String actorId;
  final String payloadJson;
  final String idempotencyScope;
  final String idempotencyKey;
  final DateTime createdAt;

  Map<String, Object?> toMap() {
    return <String, Object?>{
      'id': id,
      'dispute_id': disputeId,
      'event_type': eventType,
      'actor_id': actorId,
      'payload_json': payloadJson,
      'idempotency_scope': idempotencyScope,
      'idempotency_key': idempotencyKey,
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

  factory DisputeEventRecord.fromMap(Map<String, Object?> map) {
    return DisputeEventRecord(
      id: map['id'] as String,
      disputeId: map['dispute_id'] as String,
      eventType: map['event_type'] as String,
      actorId: map['actor_id'] as String,
      payloadJson: map['payload_json'] as String,
      idempotencyScope: map['idempotency_scope'] as String,
      idempotencyKey: map['idempotency_key'] as String,
      createdAt: DateTime.parse(map['created_at'] as String).toUtc(),
    );
  }
}
