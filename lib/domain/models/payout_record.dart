class PayoutRecord {
  const PayoutRecord({
    required this.id,
    required this.ownerId,
    required this.walletType,
    required this.amountMinor,
    required this.status,
    required this.createdAt,
    this.processedAt,
    this.idempotencyScope,
    this.idempotencyKey,
  });

  final String id;
  final String ownerId;
  final String walletType;
  final int amountMinor;
  final String status;
  final DateTime createdAt;
  final DateTime? processedAt;
  final String? idempotencyScope;
  final String? idempotencyKey;

  Map<String, Object?> toMap() {
    return <String, Object?>{
      'id': id,
      'owner_id': ownerId,
      'wallet_type': walletType,
      'amount_minor': amountMinor,
      'status': status,
      'created_at': createdAt.toUtc().toIso8601String(),
      'processed_at': processedAt?.toUtc().toIso8601String(),
      'idempotency_scope': idempotencyScope,
      'idempotency_key': idempotencyKey,
    };
  }

  factory PayoutRecord.fromMap(Map<String, Object?> map) {
    final processedAt = map['processed_at'] as String?;
    return PayoutRecord(
      id: map['id'] as String,
      ownerId: map['owner_id'] as String,
      walletType: map['wallet_type'] as String,
      amountMinor: (map['amount_minor'] as num?)?.toInt() ?? 0,
      status: map['status'] as String,
      createdAt: DateTime.parse(map['created_at'] as String).toUtc(),
      processedAt: processedAt == null
          ? null
          : DateTime.parse(processedAt).toUtc(),
      idempotencyScope: map['idempotency_scope'] as String?,
      idempotencyKey: map['idempotency_key'] as String?,
    );
  }
}
