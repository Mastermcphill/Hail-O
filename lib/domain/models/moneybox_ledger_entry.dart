class MoneyBoxLedgerEntry {
  const MoneyBoxLedgerEntry({
    required this.ownerId,
    required this.entryType,
    required this.amountMinor,
    required this.principalAfterMinor,
    required this.projectedBonusAfterMinor,
    required this.expectedAfterMinor,
    required this.sourceKind,
    required this.referenceId,
    required this.idempotencyScope,
    required this.idempotencyKey,
    required this.createdAt,
    this.id,
  });

  final int? id;
  final String ownerId;
  final String entryType;
  final int amountMinor;
  final int principalAfterMinor;
  final int projectedBonusAfterMinor;
  final int expectedAfterMinor;
  final String sourceKind;
  final String referenceId;
  final String idempotencyScope;
  final String idempotencyKey;
  final DateTime createdAt;

  Map<String, Object?> toMap() {
    return <String, Object?>{
      'id': id,
      'owner_id': ownerId,
      'entry_type': entryType,
      'amount_minor': amountMinor,
      'principal_after_minor': principalAfterMinor,
      'projected_bonus_after_minor': projectedBonusAfterMinor,
      'expected_after_minor': expectedAfterMinor,
      'source_kind': sourceKind,
      'reference_id': referenceId,
      'idempotency_scope': idempotencyScope,
      'idempotency_key': idempotencyKey,
      'created_at': createdAt.toUtc().toIso8601String(),
    };
  }

  factory MoneyBoxLedgerEntry.fromMap(Map<String, Object?> map) {
    return MoneyBoxLedgerEntry(
      id: (map['id'] as num?)?.toInt(),
      ownerId: map['owner_id'] as String,
      entryType: map['entry_type'] as String,
      amountMinor: (map['amount_minor'] as num?)?.toInt() ?? 0,
      principalAfterMinor: (map['principal_after_minor'] as num?)?.toInt() ?? 0,
      projectedBonusAfterMinor:
          (map['projected_bonus_after_minor'] as num?)?.toInt() ?? 0,
      expectedAfterMinor: (map['expected_after_minor'] as num?)?.toInt() ?? 0,
      sourceKind: map['source_kind'] as String,
      referenceId: map['reference_id'] as String,
      idempotencyScope: map['idempotency_scope'] as String,
      idempotencyKey: map['idempotency_key'] as String,
      createdAt: DateTime.parse(map['created_at'] as String).toUtc(),
    );
  }
}
