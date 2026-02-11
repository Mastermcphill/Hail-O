import 'wallet.dart';

class WalletTransfer {
  const WalletTransfer({
    required this.transferId,
    required this.fromOwnerId,
    required this.fromWalletType,
    required this.toOwnerId,
    required this.toWalletType,
    required this.amountMinor,
    required this.kind,
    required this.referenceId,
    required this.idempotencyScope,
    required this.idempotencyKey,
    required this.createdAt,
  });

  final String transferId;
  final String fromOwnerId;
  final WalletType fromWalletType;
  final String toOwnerId;
  final WalletType toWalletType;
  final int amountMinor;
  final String kind;
  final String referenceId;
  final String idempotencyScope;
  final String idempotencyKey;
  final DateTime createdAt;

  Map<String, Object?> toMap() {
    return <String, Object?>{
      'transfer_id': transferId,
      'from_owner_id': fromOwnerId,
      'from_wallet_type': fromWalletType.dbValue,
      'to_owner_id': toOwnerId,
      'to_wallet_type': toWalletType.dbValue,
      'amount_minor': amountMinor,
      'kind': kind,
      'reference_id': referenceId,
      'idempotency_scope': idempotencyScope,
      'idempotency_key': idempotencyKey,
      'created_at': createdAt.toUtc().toIso8601String(),
    };
  }

  factory WalletTransfer.fromMap(Map<String, Object?> map) {
    return WalletTransfer(
      transferId: map['transfer_id'] as String,
      fromOwnerId: map['from_owner_id'] as String,
      fromWalletType: WalletType.fromDbValue(map['from_wallet_type'] as String),
      toOwnerId: map['to_owner_id'] as String,
      toWalletType: WalletType.fromDbValue(map['to_wallet_type'] as String),
      amountMinor: (map['amount_minor'] as num?)?.toInt() ?? 0,
      kind: map['kind'] as String,
      referenceId: map['reference_id'] as String,
      idempotencyScope: map['idempotency_scope'] as String,
      idempotencyKey: map['idempotency_key'] as String,
      createdAt: DateTime.parse(map['created_at'] as String).toUtc(),
    );
  }
}
