class PenaltyRecord {
  const PenaltyRecord({
    required this.id,
    required this.userId,
    required this.penaltyKind,
    required this.amountMinor,
    required this.createdAt,
    this.reason,
    this.idempotencyScope,
    this.idempotencyKey,
  });

  final String id;
  final String userId;
  final String penaltyKind;
  final int amountMinor;
  final String? reason;
  final DateTime createdAt;
  final String? idempotencyScope;
  final String? idempotencyKey;

  Map<String, Object?> toMap() {
    return <String, Object?>{
      'id': id,
      'user_id': userId,
      'penalty_kind': penaltyKind,
      'amount_minor': amountMinor,
      'reason': reason,
      'created_at': createdAt.toUtc().toIso8601String(),
      'idempotency_scope': idempotencyScope,
      'idempotency_key': idempotencyKey,
    };
  }

  factory PenaltyRecord.fromMap(Map<String, Object?> map) {
    return PenaltyRecord(
      id: map['id'] as String,
      userId: map['user_id'] as String,
      penaltyKind: map['penalty_kind'] as String,
      amountMinor: (map['amount_minor'] as num?)?.toInt() ?? 0,
      reason: map['reason'] as String?,
      createdAt: DateTime.parse(map['created_at'] as String).toUtc(),
      idempotencyScope: map['idempotency_scope'] as String?,
      idempotencyKey: map['idempotency_key'] as String?,
    );
  }
}
