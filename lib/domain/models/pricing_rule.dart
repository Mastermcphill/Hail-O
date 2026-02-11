class PricingRule {
  const PricingRule({
    required this.version,
    required this.effectiveFrom,
    required this.scope,
    required this.parametersJson,
    required this.createdAt,
  });

  final String version;
  final DateTime effectiveFrom;
  final String scope;
  final String parametersJson;
  final DateTime createdAt;

  Map<String, Object?> toMap() {
    return <String, Object?>{
      'version': version,
      'effective_from': effectiveFrom.toUtc().toIso8601String(),
      'scope': scope,
      'parameters_json': parametersJson,
      'created_at': createdAt.toUtc().toIso8601String(),
    };
  }

  factory PricingRule.fromMap(Map<String, Object?> map) {
    return PricingRule(
      version: map['version'] as String,
      effectiveFrom: DateTime.parse(map['effective_from'] as String).toUtc(),
      scope: map['scope'] as String,
      parametersJson: map['parameters_json'] as String,
      createdAt: DateTime.parse(map['created_at'] as String).toUtc(),
    );
  }
}
