class EscrowHold {
  const EscrowHold({
    required this.id,
    required this.rideId,
    required this.holderUserId,
    required this.amountMinor,
    required this.status,
    required this.createdAt,
    this.releaseMode,
    this.releasedAt,
    this.idempotencyScope,
    this.idempotencyKey,
  });

  final String id;
  final String rideId;
  final String holderUserId;
  final int amountMinor;
  final String status;
  final String? releaseMode;
  final DateTime createdAt;
  final DateTime? releasedAt;
  final String? idempotencyScope;
  final String? idempotencyKey;

  Map<String, Object?> toMap() {
    return <String, Object?>{
      'id': id,
      'ride_id': rideId,
      'holder_user_id': holderUserId,
      'amount_minor': amountMinor,
      'status': status,
      'release_mode': releaseMode,
      'created_at': createdAt.toUtc().toIso8601String(),
      'released_at': releasedAt?.toUtc().toIso8601String(),
      'idempotency_scope': idempotencyScope,
      'idempotency_key': idempotencyKey,
    };
  }

  factory EscrowHold.fromMap(Map<String, Object?> map) {
    final releasedAt = map['released_at'] as String?;
    return EscrowHold(
      id: map['id'] as String,
      rideId: map['ride_id'] as String,
      holderUserId: map['holder_user_id'] as String,
      amountMinor: (map['amount_minor'] as num?)?.toInt() ?? 0,
      status: map['status'] as String,
      releaseMode: map['release_mode'] as String?,
      createdAt: DateTime.parse(map['created_at'] as String).toUtc(),
      releasedAt: releasedAt == null
          ? null
          : DateTime.parse(releasedAt).toUtc(),
      idempotencyScope: map['idempotency_scope'] as String?,
      idempotencyKey: map['idempotency_key'] as String?,
    );
  }
}
