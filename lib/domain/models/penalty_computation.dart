class PenaltyComputation {
  const PenaltyComputation({
    required this.penaltyMinor,
    required this.ruleCode,
    this.percentApplied,
    this.fixedFeeMinor,
    this.note = '',
  });

  final int penaltyMinor;
  final String ruleCode;
  final int? percentApplied;
  final int? fixedFeeMinor;
  final String note;

  Map<String, Object?> toMap() {
    return <String, Object?>{
      'penalty_minor': penaltyMinor,
      'rule_code': ruleCode,
      'percent_applied': percentApplied,
      'fixed_fee_minor': fixedFeeMinor,
      'note': note,
    };
  }
}
