enum MoneyBoxTier {
  tier1(1),
  tier2(2),
  tier3(3),
  tier4(4);

  const MoneyBoxTier(this.value);

  final int value;

  static MoneyBoxTier fromValue(int value) {
    return MoneyBoxTier.values.firstWhere(
      (tier) => tier.value == value,
      orElse: () => MoneyBoxTier.tier1,
    );
  }
}

class MoneyBoxAccount {
  const MoneyBoxAccount({
    required this.ownerId,
    required this.tier,
    required this.status,
    required this.principalMinor,
    required this.projectedBonusMinor,
    required this.expectedAtMaturityMinor,
    required this.autosavePercent,
    required this.bonusEligible,
    required this.createdAt,
    required this.updatedAt,
    this.lockStart,
    this.autoOpenDate,
    this.maturityDate,
  });

  final String ownerId;
  final MoneyBoxTier tier;
  final String status;
  final DateTime? lockStart;
  final DateTime? autoOpenDate;
  final DateTime? maturityDate;
  final int principalMinor;
  final int projectedBonusMinor;
  final int expectedAtMaturityMinor;
  final int autosavePercent;
  final bool bonusEligible;
  final DateTime createdAt;
  final DateTime updatedAt;

  Map<String, Object?> toMap() {
    return <String, Object?>{
      'owner_id': ownerId,
      'tier': tier.value,
      'status': status,
      'lock_start': lockStart?.toUtc().toIso8601String(),
      'auto_open_date': autoOpenDate?.toUtc().toIso8601String(),
      'maturity_date': maturityDate?.toUtc().toIso8601String(),
      'principal_minor': principalMinor,
      'projected_bonus_minor': projectedBonusMinor,
      'expected_at_maturity_minor': expectedAtMaturityMinor,
      'autosave_percent': autosavePercent,
      'bonus_eligible': bonusEligible ? 1 : 0,
      'created_at': createdAt.toUtc().toIso8601String(),
      'updated_at': updatedAt.toUtc().toIso8601String(),
    };
  }

  factory MoneyBoxAccount.fromMap(Map<String, Object?> map) {
    DateTime? parseNullable(String key) {
      final value = map[key] as String?;
      return value == null ? null : DateTime.parse(value).toUtc();
    }

    return MoneyBoxAccount(
      ownerId: map['owner_id'] as String,
      tier: MoneyBoxTier.fromValue((map['tier'] as num?)?.toInt() ?? 1),
      status: map['status'] as String,
      lockStart: parseNullable('lock_start'),
      autoOpenDate: parseNullable('auto_open_date'),
      maturityDate: parseNullable('maturity_date'),
      principalMinor: (map['principal_minor'] as num?)?.toInt() ?? 0,
      projectedBonusMinor: (map['projected_bonus_minor'] as num?)?.toInt() ?? 0,
      expectedAtMaturityMinor:
          (map['expected_at_maturity_minor'] as num?)?.toInt() ?? 0,
      autosavePercent: (map['autosave_percent'] as num?)?.toInt() ?? 0,
      bonusEligible: ((map['bonus_eligible'] as num?)?.toInt() ?? 0) == 1,
      createdAt: DateTime.parse(map['created_at'] as String).toUtc(),
      updatedAt: DateTime.parse(map['updated_at'] as String).toUtc(),
    );
  }
}
