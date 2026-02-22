class PromoEvent {
  const PromoEvent({
    required this.id,
    required this.eventType,
    required this.userId,
    required this.amountMinor,
    required this.status,
    required this.createdAt,
    this.relatedUserId,
    this.idempotencyScope,
    this.idempotencyKey,
  });

  final String id;
  final String eventType;
  final String userId;
  final String? relatedUserId;
  final int amountMinor;
  final String status;
  final DateTime createdAt;
  final String? idempotencyScope;
  final String? idempotencyKey;

  Map<String, Object?> toMap() {
    return <String, Object?>{
      'id': id,
      'event_type': eventType,
      'user_id': userId,
      'related_user_id': relatedUserId,
      'amount_minor': amountMinor,
      'status': status,
      'created_at': createdAt.toUtc().toIso8601String(),
      'idempotency_scope': idempotencyScope,
      'idempotency_key': idempotencyKey,
    };
  }

  factory PromoEvent.fromMap(Map<String, Object?> map) {
    return PromoEvent(
      id: map['id'] as String,
      eventType: map['event_type'] as String,
      userId: map['user_id'] as String,
      relatedUserId: map['related_user_id'] as String?,
      amountMinor: (map['amount_minor'] as num?)?.toInt() ?? 0,
      status: map['status'] as String,
      createdAt: DateTime.parse(map['created_at'] as String).toUtc(),
      idempotencyScope: map['idempotency_scope'] as String?,
      idempotencyKey: map['idempotency_key'] as String?,
    );
  }
}
