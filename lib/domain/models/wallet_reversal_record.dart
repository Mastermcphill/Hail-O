class WalletReversalRecord {
  const WalletReversalRecord({
    required this.id,
    required this.originalLedgerId,
    required this.reversalLedgerId,
    required this.requestedByUserId,
    required this.reason,
    required this.idempotencyScope,
    required this.idempotencyKey,
    required this.createdAt,
  });

  final String id;
  final int originalLedgerId;
  final int reversalLedgerId;
  final String requestedByUserId;
  final String reason;
  final String idempotencyScope;
  final String idempotencyKey;
  final DateTime createdAt;

  Map<String, Object?> toMap() {
    return <String, Object?>{
      'id': id,
      'original_ledger_id': originalLedgerId,
      'reversal_ledger_id': reversalLedgerId,
      'requested_by_user_id': requestedByUserId,
      'reason': reason,
      'idempotency_scope': idempotencyScope,
      'idempotency_key': idempotencyKey,
      'created_at': createdAt.toUtc().toIso8601String(),
    };
  }

  factory WalletReversalRecord.fromMap(Map<String, Object?> map) {
    return WalletReversalRecord(
      id: map['id'] as String,
      originalLedgerId: (map['original_ledger_id'] as num).toInt(),
      reversalLedgerId: (map['reversal_ledger_id'] as num).toInt(),
      requestedByUserId: map['requested_by_user_id'] as String,
      reason: map['reason'] as String,
      idempotencyScope: map['idempotency_scope'] as String,
      idempotencyKey: map['idempotency_key'] as String,
      createdAt: DateTime.parse(map['created_at'] as String).toUtc(),
    );
  }
}
