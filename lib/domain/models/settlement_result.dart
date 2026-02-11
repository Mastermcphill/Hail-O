import 'wallet.dart';

enum SettlementTrigger {
  arrivalGeofence('geofence'),
  manualOverride('manual_override');

  const SettlementTrigger(this.dbValue);
  final String dbValue;

  static SettlementTrigger fromDbValue(String value) {
    return SettlementTrigger.values.firstWhere(
      (trigger) => trigger.dbValue == value,
      orElse: () => SettlementTrigger.manualOverride,
    );
  }
}

class SettlementResult {
  const SettlementResult({
    required this.ok,
    required this.rideId,
    required this.escrowId,
    required this.trigger,
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
    this.replayed = false,
    this.resultHash,
    this.error,
  });

  final bool ok;
  final String rideId;
  final String escrowId;
  final SettlementTrigger trigger;
  final String recipientOwnerId;
  final WalletType recipientWalletType;
  final int totalPaidMinor;
  final int commissionGrossMinor;
  final int commissionSavedMinor;
  final int commissionRemainderMinor;
  final int premiumLockedMinor;
  final int driverAllowanceMinor;
  final int cashDebtMinor;
  final int penaltyDueMinor;
  final bool replayed;
  final String? resultHash;
  final String? error;

  Map<String, Object?> toMap() {
    return <String, Object?>{
      'ok': ok,
      'ride_id': rideId,
      'escrow_id': escrowId,
      'trigger': trigger.dbValue,
      'recipient_owner_id': recipientOwnerId,
      'recipient_wallet_type': recipientWalletType.dbValue,
      'total_paid_minor': totalPaidMinor,
      'commission_gross_minor': commissionGrossMinor,
      'commission_saved_minor': commissionSavedMinor,
      'commission_remainder_minor': commissionRemainderMinor,
      'premium_locked_minor': premiumLockedMinor,
      'driver_allowance_minor': driverAllowanceMinor,
      'cash_debt_minor': cashDebtMinor,
      'penalty_due_minor': penaltyDueMinor,
      'replayed': replayed,
      'result_hash': resultHash,
      'error': error,
    };
  }

  SettlementResult copyWith({
    bool? ok,
    bool? replayed,
    String? resultHash,
    String? error,
  }) {
    return SettlementResult(
      ok: ok ?? this.ok,
      rideId: rideId,
      escrowId: escrowId,
      trigger: trigger,
      recipientOwnerId: recipientOwnerId,
      recipientWalletType: recipientWalletType,
      totalPaidMinor: totalPaidMinor,
      commissionGrossMinor: commissionGrossMinor,
      commissionSavedMinor: commissionSavedMinor,
      commissionRemainderMinor: commissionRemainderMinor,
      premiumLockedMinor: premiumLockedMinor,
      driverAllowanceMinor: driverAllowanceMinor,
      cashDebtMinor: cashDebtMinor,
      penaltyDueMinor: penaltyDueMinor,
      replayed: replayed ?? this.replayed,
      resultHash: resultHash ?? this.resultHash,
      error: error ?? this.error,
    );
  }

  factory SettlementResult.error({
    required String rideId,
    required String escrowId,
    required String error,
    String? resultHash,
    bool replayed = false,
  }) {
    return SettlementResult(
      ok: false,
      rideId: rideId,
      escrowId: escrowId,
      trigger: SettlementTrigger.manualOverride,
      recipientOwnerId: '',
      recipientWalletType: WalletType.driverA,
      totalPaidMinor: 0,
      commissionGrossMinor: 0,
      commissionSavedMinor: 0,
      commissionRemainderMinor: 0,
      premiumLockedMinor: 0,
      driverAllowanceMinor: 0,
      cashDebtMinor: 0,
      penaltyDueMinor: 0,
      replayed: replayed,
      resultHash: resultHash,
      error: error,
    );
  }
}
