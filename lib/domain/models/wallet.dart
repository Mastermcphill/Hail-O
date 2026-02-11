enum WalletType {
  driverA('driver_a'),
  driverB('driver_b'),
  driverC('driver_c'),
  fleetOwner('fleet_owner'),
  platform('platform');

  const WalletType(this.dbValue);

  final String dbValue;

  static WalletType fromDbValue(String value) {
    return WalletType.values.firstWhere(
      (type) => type.dbValue == value,
      orElse: () => WalletType.driverA,
    );
  }
}

class Wallet {
  const Wallet({
    required this.ownerId,
    required this.walletType,
    required this.balanceMinor,
    required this.reservedMinor,
    required this.currency,
    required this.updatedAt,
    required this.createdAt,
  });

  final String ownerId;
  final WalletType walletType;
  final int balanceMinor;
  final int reservedMinor;
  final String currency;
  final DateTime updatedAt;
  final DateTime createdAt;

  Map<String, Object?> toMap() {
    return <String, Object?>{
      'owner_id': ownerId,
      'wallet_type': walletType.dbValue,
      'balance_minor': balanceMinor,
      'reserved_minor': reservedMinor,
      'currency': currency,
      'updated_at': updatedAt.toUtc().toIso8601String(),
      'created_at': createdAt.toUtc().toIso8601String(),
    };
  }

  factory Wallet.fromMap(Map<String, Object?> map) {
    return Wallet(
      ownerId: map['owner_id'] as String,
      walletType: WalletType.fromDbValue(map['wallet_type'] as String),
      balanceMinor: (map['balance_minor'] as num?)?.toInt() ?? 0,
      reservedMinor: (map['reserved_minor'] as num?)?.toInt() ?? 0,
      currency: map['currency'] as String? ?? 'NGN',
      updatedAt: DateTime.parse(map['updated_at'] as String).toUtc(),
      createdAt: DateTime.parse(map['created_at'] as String).toUtc(),
    );
  }
}
