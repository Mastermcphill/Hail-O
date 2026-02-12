class PenaltyRule {
  const PenaltyRule({
    required this.version,
    required this.effectiveFrom,
    required this.scope,
    required this.parametersJson,
    required this.createdAt,
    this.enabled = true,
    this.rolloutPercent = 100,
    this.rolloutSalt = 'default',
  });

  final String version;
  final DateTime effectiveFrom;
  final String scope;
  final String parametersJson;
  final DateTime createdAt;
  final bool enabled;
  final int rolloutPercent;
  final String rolloutSalt;

  Map<String, Object?> toMap() {
    return <String, Object?>{
      'version': version,
      'effective_from': effectiveFrom.toUtc().toIso8601String(),
      'scope': scope,
      'parameters_json': parametersJson,
      'created_at': createdAt.toUtc().toIso8601String(),
      'enabled': enabled ? 1 : 0,
      'rollout_percent': rolloutPercent,
      'rollout_salt': rolloutSalt,
    };
  }

  factory PenaltyRule.fromMap(Map<String, Object?> map) {
    return PenaltyRule(
      version: map['version'] as String,
      effectiveFrom: DateTime.parse(map['effective_from'] as String).toUtc(),
      scope: map['scope'] as String,
      parametersJson: map['parameters_json'] as String,
      createdAt: DateTime.parse(map['created_at'] as String).toUtc(),
      enabled: ((map['enabled'] as num?)?.toInt() ?? 1) == 1,
      rolloutPercent: (map['rollout_percent'] as num?)?.toInt() ?? 100,
      rolloutSalt: (map['rollout_salt'] as String?) ?? 'default',
    );
  }
}
