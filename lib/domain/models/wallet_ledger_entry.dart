import 'wallet.dart';

enum LedgerDirection {
  credit('credit'),
  debit('debit');

  const LedgerDirection(this.dbValue);

  final String dbValue;

  static LedgerDirection fromDbValue(String value) {
    return LedgerDirection.values.firstWhere(
      (direction) => direction.dbValue == value,
      orElse: () => LedgerDirection.credit,
    );
  }
}

class WalletLedgerEntry {
  const WalletLedgerEntry({
    required this.ownerId,
    required this.walletType,
    required this.direction,
    required this.amountMinor,
    required this.balanceAfterMinor,
    required this.kind,
    required this.referenceId,
    required this.idempotencyScope,
    required this.idempotencyKey,
    required this.createdAt,
    this.id,
  });

  final int? id;
  final String ownerId;
  final WalletType walletType;
  final LedgerDirection direction;
  final int amountMinor;
  final int balanceAfterMinor;
  final String kind;
  final String referenceId;
  final String idempotencyScope;
  final String idempotencyKey;
  final DateTime createdAt;

  Map<String, Object?> toMap() {
    return <String, Object?>{
      'id': id,
      'owner_id': ownerId,
      'wallet_type': walletType.dbValue,
      'direction': direction.dbValue,
      'amount_minor': amountMinor,
      'balance_after_minor': balanceAfterMinor,
      'kind': kind,
      'reference_id': referenceId,
      'idempotency_scope': idempotencyScope,
      'idempotency_key': idempotencyKey,
      'created_at': createdAt.toUtc().toIso8601String(),
    };
  }

  factory WalletLedgerEntry.fromMap(Map<String, Object?> map) {
    return WalletLedgerEntry(
      id: (map['id'] as num?)?.toInt(),
      ownerId: map['owner_id'] as String,
      walletType: WalletType.fromDbValue(map['wallet_type'] as String),
      direction: LedgerDirection.fromDbValue(map['direction'] as String),
      amountMinor: (map['amount_minor'] as num?)?.toInt() ?? 0,
      balanceAfterMinor: (map['balance_after_minor'] as num?)?.toInt() ?? 0,
      kind: map['kind'] as String,
      referenceId: map['reference_id'] as String,
      idempotencyScope: map['idempotency_scope'] as String,
      idempotencyKey: map['idempotency_key'] as String,
      createdAt: DateTime.parse(map['created_at'] as String).toUtc(),
    );
  }
}
