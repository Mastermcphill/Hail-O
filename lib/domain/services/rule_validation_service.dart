import 'dart:convert';

class RuleValidationResult {
  const RuleValidationResult({required this.ok, required this.errors});

  final bool ok;
  final List<String> errors;
}

class RuleValidationService {
  const RuleValidationService();

  RuleValidationResult validatePricingRuleJson(String rawJson) {
    final errors = <String>[];
    final decoded = _decodeMap(rawJson, errors);
    if (decoded == null) {
      return RuleValidationResult(ok: false, errors: errors);
    }
    _requireMapWithNumericValues(decoded, 'base_fare_minor', errors);
    _requireMapWithNumericValues(decoded, 'distance_rate_per_km_minor', errors);
    _requireMapWithNumericValues(decoded, 'time_rate_per_min_minor', errors);
    _requireMapWithNumericValues(decoded, 'vehicle_multiplier_percent', errors);
    _requireInt(
      decoded,
      'luggage_surcharge_per_extra_minor',
      min: 0,
      errors: errors,
    );
    final windows = decoded['surge_windows'];
    if (windows is! List) {
      errors.add('surge_windows must be a list');
    }
    return RuleValidationResult(ok: errors.isEmpty, errors: errors);
  }

  RuleValidationResult validatePenaltyRuleJson(String rawJson) {
    final errors = <String>[];
    final decoded = _decodeMap(rawJson, errors);
    if (decoded == null) {
      return RuleValidationResult(ok: false, errors: errors);
    }
    final intra = _requireMap(decoded, 'intra', errors);
    final inter = _requireMap(decoded, 'inter', errors);
    final international = _requireMap(decoded, 'international', errors);
    if (intra != null) {
      _requireInt(intra, 'late_fee_minor', min: 0, errors: errors);
      if (intra['late_if_cancelled_at_or_after_departure'] is! bool) {
        errors.add(
          'intra.late_if_cancelled_at_or_after_departure must be bool',
        );
      }
    }
    if (inter != null) {
      _requireInt(inter, 'gt_hours', min: 0, errors: errors);
      _requireInt(inter, 'gt_hours_percent', min: 0, max: 100, errors: errors);
      _requireInt(inter, 'lte_hours_percent', min: 0, max: 100, errors: errors);
    }
    if (international != null) {
      _requireInt(international, 'lt_hours', min: 0, errors: errors);
      _requireInt(
        international,
        'lt_hours_percent',
        min: 0,
        max: 100,
        errors: errors,
      );
      _requireInt(
        international,
        'gte_hours_percent',
        min: 0,
        max: 100,
        errors: errors,
      );
    }
    return RuleValidationResult(ok: errors.isEmpty, errors: errors);
  }

  RuleValidationResult validateComplianceRequirementJson(String rawJson) {
    final errors = <String>[];
    final decoded = _decodeMap(rawJson, errors);
    if (decoded == null) {
      return RuleValidationResult(ok: false, errors: errors);
    }
    if (decoded['requires_next_of_kin'] is! bool) {
      errors.add('requires_next_of_kin must be bool');
    }
    final docs = decoded['allowed_doc_types'];
    if (docs is! List) {
      errors.add('allowed_doc_types must be a list');
    }
    if (decoded['requires_verified'] is! bool) {
      errors.add('requires_verified must be bool');
    }
    if (decoded['requires_not_expired'] is! bool) {
      errors.add('requires_not_expired must be bool');
    }
    return RuleValidationResult(ok: errors.isEmpty, errors: errors);
  }

  Map<String, dynamic>? _decodeMap(String rawJson, List<String> errors) {
    try {
      final decoded = jsonDecode(rawJson);
      if (decoded is! Map<String, dynamic>) {
        errors.add('rule json must decode to object');
        return null;
      }
      return decoded;
    } catch (_) {
      errors.add('rule json is invalid');
      return null;
    }
  }

  Map<String, dynamic>? _requireMap(
    Map<String, dynamic> parent,
    String key,
    List<String> errors,
  ) {
    final value = parent[key];
    if (value is! Map<String, dynamic>) {
      errors.add('$key must be an object');
      return null;
    }
    return value;
  }

  void _requireMapWithNumericValues(
    Map<String, dynamic> parent,
    String key,
    List<String> errors,
  ) {
    final value = parent[key];
    if (value is! Map) {
      errors.add('$key must be object');
      return;
    }
    for (final entry in value.entries) {
      if (entry.value is! num) {
        errors.add('$key.${entry.key} must be numeric');
      }
    }
  }

  void _requireInt(
    Map<String, dynamic> parent,
    String key, {
    required List<String> errors,
    int? min,
    int? max,
  }) {
    final value = parent[key];
    if (value is! num) {
      errors.add('$key must be numeric');
      return;
    }
    final intValue = value.toInt();
    if (min != null && intValue < min) {
      errors.add('$key must be >= $min');
    }
    if (max != null && intValue > max) {
      errors.add('$key must be <= $max');
    }
  }
}
