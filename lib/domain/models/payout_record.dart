class PayoutRecord {
  const PayoutRecord({
    required this.id,
    required this.rideId,
    required this.escrowId,
    required this.trigger,
    required this.status,
    required this.recipientOwnerId,
    required this.recipientWalletType,
    required this.totalPaidMinor,
    required this.commissionGrossMinor,
    required this.commissionSavedMinor,
    required this.commissionRemainderMinor,
    required this.premiumLockedMinor,
    required this.driverAllowanceMinor,
    required this.cashDebtMinor,
    required this.penaltyDueMinor,
    required this.breakdownJson,
    required this.idempotencyScope,
    required this.idempotencyKey,
    required this.createdAt,
  });

  final String id;
  final String rideId;
  final String escrowId;
  final String trigger;
  final String status;
  final String recipientOwnerId;
  final String recipientWalletType;
  final int totalPaidMinor;
  final int commissionGrossMinor;
  final int commissionSavedMinor;
  final int commissionRemainderMinor;
  final int premiumLockedMinor;
  final int driverAllowanceMinor;
  final int cashDebtMinor;
  final int penaltyDueMinor;
  final String breakdownJson;
  final String idempotencyScope;
  final String idempotencyKey;
  final DateTime createdAt;

  Map<String, Object?> toMap() {
    return <String, Object?>{
      'id': id,
      'ride_id': rideId,
      'escrow_id': escrowId,
      'trigger': trigger,
      'status': status,
      'recipient_owner_id': recipientOwnerId,
      'recipient_wallet_type': recipientWalletType,
      'total_paid_minor': totalPaidMinor,
      'commission_gross_minor': commissionGrossMinor,
      'commission_saved_minor': commissionSavedMinor,
      'commission_remainder_minor': commissionRemainderMinor,
      'premium_locked_minor': premiumLockedMinor,
      'driver_allowance_minor': driverAllowanceMinor,
      'cash_debt_minor': cashDebtMinor,
      'penalty_due_minor': penaltyDueMinor,
      'breakdown_json': breakdownJson,
      'idempotency_scope': idempotencyScope,
      'idempotency_key': idempotencyKey,
      'created_at': createdAt.toUtc().toIso8601String(),
    };
  }

  factory PayoutRecord.fromMap(Map<String, Object?> map) {
    return PayoutRecord(
      id: map['id'] as String,
      rideId: map['ride_id'] as String,
      escrowId: map['escrow_id'] as String,
      trigger: map['trigger'] as String,
      status: map['status'] as String,
      recipientOwnerId: map['recipient_owner_id'] as String,
      recipientWalletType: map['recipient_wallet_type'] as String,
      totalPaidMinor: (map['total_paid_minor'] as num?)?.toInt() ?? 0,
      commissionGrossMinor:
          (map['commission_gross_minor'] as num?)?.toInt() ?? 0,
      commissionSavedMinor:
          (map['commission_saved_minor'] as num?)?.toInt() ?? 0,
      commissionRemainderMinor:
          (map['commission_remainder_minor'] as num?)?.toInt() ?? 0,
      premiumLockedMinor: (map['premium_locked_minor'] as num?)?.toInt() ?? 0,
      driverAllowanceMinor:
          (map['driver_allowance_minor'] as num?)?.toInt() ?? 0,
      cashDebtMinor: (map['cash_debt_minor'] as num?)?.toInt() ?? 0,
      penaltyDueMinor: (map['penalty_due_minor'] as num?)?.toInt() ?? 0,
      breakdownJson: map['breakdown_json'] as String? ?? '{}',
      idempotencyScope: map['idempotency_scope'] as String,
      idempotencyKey: map['idempotency_key'] as String,
      createdAt: DateTime.parse(map['created_at'] as String).toUtc(),
    );
  }
}
