class PenaltyAuditRecord {
  const PenaltyAuditRecord({
    required this.id,
    required this.rideId,
    required this.userId,
    required this.amountMinor,
    required this.ruleCode,
    required this.status,
    required this.idempotencyScope,
    required this.idempotencyKey,
    required this.createdAt,
    this.rideType,
    this.totalFareMinor,
    this.collectedToOwnerId,
    this.collectedToWalletType,
  });

  final String id;
  final String? rideId;
  final String userId;
  final int amountMinor;
  final String ruleCode;
  final String status;
  final String? rideType;
  final int? totalFareMinor;
  final String? collectedToOwnerId;
  final String? collectedToWalletType;
  final String idempotencyScope;
  final String idempotencyKey;
  final DateTime createdAt;

  Map<String, Object?> toMap() {
    return <String, Object?>{
      'id': id,
      'ride_id': rideId,
      'user_id': userId,
      'amount_minor': amountMinor,
      'ride_type': rideType,
      'total_fare_minor': totalFareMinor,
      'rule_code': ruleCode,
      'status': status,
      'collected_to_owner_id': collectedToOwnerId,
      'collected_to_wallet_type': collectedToWalletType,
      'idempotency_scope': idempotencyScope,
      'idempotency_key': idempotencyKey,
      'created_at': createdAt.toUtc().toIso8601String(),
    };
  }

  factory PenaltyAuditRecord.fromMap(Map<String, Object?> map) {
    return PenaltyAuditRecord(
      id: map['id'] as String,
      rideId: map['ride_id'] as String?,
      userId: map['user_id'] as String,
      amountMinor: (map['amount_minor'] as num?)?.toInt() ?? 0,
      ruleCode: map['rule_code'] as String,
      status: map['status'] as String,
      rideType: map['ride_type'] as String?,
      totalFareMinor: (map['total_fare_minor'] as num?)?.toInt(),
      collectedToOwnerId: map['collected_to_owner_id'] as String?,
      collectedToWalletType: map['collected_to_wallet_type'] as String?,
      idempotencyScope: map['idempotency_scope'] as String,
      idempotencyKey: map['idempotency_key'] as String,
      createdAt: DateTime.parse(map['created_at'] as String).toUtc(),
    );
  }
}
