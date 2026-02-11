class PricingQuote {
  const PricingQuote({
    required this.fareMinor,
    required this.ruleVersion,
    required this.breakdownJson,
  });

  final int fareMinor;
  final String ruleVersion;
  final String breakdownJson;

  Map<String, Object?> toMap() {
    return <String, Object?>{
      'fare_minor': fareMinor,
      'rule_version': ruleVersion,
      'breakdown_json': breakdownJson,
    };
  }
}
