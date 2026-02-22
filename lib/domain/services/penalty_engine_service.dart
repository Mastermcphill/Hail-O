import 'dart:convert';

import 'package:hail_o_finance_core/sqlite_api.dart';

import '../../data/sqlite/dao/penalty_rules_dao.dart';
import '../models/penalty_computation.dart';
import 'rule_rollout_service.dart';
import 'rule_validation_service.dart';

enum RideType {
  intra('intra'),
  inter('inter'),
  international('international');

  const RideType(this.dbValue);
  final String dbValue;
}

class PenaltyEngineService {
  const PenaltyEngineService({this.ruleVersion = 'penalty_v1'})
    : _policy = _PenaltyPolicy.defaultPolicy;

  static Future<PenaltyEngineService> fromDatabase(
    DatabaseExecutor db, {
    required DateTime asOfUtc,
    String scope = 'default',
    String? subjectId,
    RuleRolloutService rolloutService = const RuleRolloutService(),
    RuleValidationService validationService = const RuleValidationService(),
  }) async {
    final rules = await PenaltyRulesDao(
      db,
    ).listActiveRules(asOfUtc: asOfUtc, scope: scope);
    if (rules.isEmpty) {
      return const PenaltyEngineService();
    }
    for (final rule in rules) {
      final validation = validationService.validatePenaltyRuleJson(
        rule.parametersJson,
      );
      if (!validation.ok) {
        continue;
      }
      if (subjectId != null &&
          !rolloutService.isInRollout(
            subjectId: subjectId,
            percent: rule.rolloutPercent,
            salt: rule.rolloutSalt,
          )) {
        continue;
      }
      return PenaltyEngineService._(
        policy: _PenaltyPolicy.fromJson(rule.parametersJson),
        ruleVersion: rule.version,
      );
    }
    return const PenaltyEngineService();
  }

  const PenaltyEngineService._({
    required _PenaltyPolicy policy,
    required this.ruleVersion,
  }) : _policy = policy;

  final _PenaltyPolicy _policy;
  final String ruleVersion;

  PenaltyComputation computeCancellationPenaltyMinor({
    required RideType rideType,
    required int totalFareMinor,
    required DateTime scheduledDeparture,
    required DateTime cancelledAt,
  }) {
    final departure = scheduledDeparture.toUtc();
    final cancelled = cancelledAt.toUtc();
    final timeBeforeDepartureHours = departure.difference(cancelled).inHours;

    if (rideType == RideType.intra) {
      // Exact deterministic interpretation requested:
      // apply fixed N500 (50000 minor) only when cancellation is at/after departure.
      final isLate = !cancelled.isBefore(departure);
      final fee = isLate && _policy.intraLateWhenAfterDeparture
          ? _policy.intraLateFeeMinor
          : 0;
      return PenaltyComputation(
        penaltyMinor: fee,
        ruleCode: fee > 0
            ? 'intra_cancel_at_or_after_departure_fixed_500'
            : 'intra_cancel_before_departure_no_penalty',
        fixedFeeMinor: fee > 0 ? fee : null,
        note: fee > 0
            ? 'Cancelled at or after scheduled departure.'
            : 'Cancelled before scheduled departure.',
      );
    }

    if (rideType == RideType.inter) {
      final percentApplied =
          timeBeforeDepartureHours > _policy.interGreaterThanHours
          ? _policy.interGreaterThanHoursPercent
          : _policy.interLessOrEqualHoursPercent;
      return PenaltyComputation(
        penaltyMinor: (totalFareMinor * percentApplied) ~/ 100,
        ruleCode: percentApplied == _policy.interGreaterThanHoursPercent
            ? 'inter_cancel_gt_10h_10pct'
            : 'inter_cancel_lte_10h_30pct',
        percentApplied: percentApplied,
        note: 'Inter-state cancellation rule.',
      );
    }

    final percentApplied =
        timeBeforeDepartureHours < _policy.internationalLessThanHours
        ? _policy.internationalLessThanHoursPercent
        : _policy.internationalGreaterOrEqualHoursPercent;
    return PenaltyComputation(
      penaltyMinor: (totalFareMinor * percentApplied) ~/ 100,
      ruleCode: percentApplied == _policy.internationalLessThanHoursPercent
          ? 'international_cancel_lt_24h_50pct'
          : 'international_cancel_gte_24h_0pct',
      percentApplied: percentApplied,
      note: 'International cancellation rule.',
    );
  }
}

class _PenaltyPolicy {
  const _PenaltyPolicy({
    required this.intraLateFeeMinor,
    required this.intraLateWhenAfterDeparture,
    required this.interGreaterThanHours,
    required this.interGreaterThanHoursPercent,
    required this.interLessOrEqualHoursPercent,
    required this.internationalLessThanHours,
    required this.internationalLessThanHoursPercent,
    required this.internationalGreaterOrEqualHoursPercent,
  });

  static const _PenaltyPolicy defaultPolicy = _PenaltyPolicy(
    intraLateFeeMinor: 50000,
    intraLateWhenAfterDeparture: true,
    interGreaterThanHours: 10,
    interGreaterThanHoursPercent: 10,
    interLessOrEqualHoursPercent: 30,
    internationalLessThanHours: 24,
    internationalLessThanHoursPercent: 50,
    internationalGreaterOrEqualHoursPercent: 0,
  );

  final int intraLateFeeMinor;
  final bool intraLateWhenAfterDeparture;
  final int interGreaterThanHours;
  final int interGreaterThanHoursPercent;
  final int interLessOrEqualHoursPercent;
  final int internationalLessThanHours;
  final int internationalLessThanHoursPercent;
  final int internationalGreaterOrEqualHoursPercent;

  factory _PenaltyPolicy.fromJson(String rawJson) {
    final fallback = defaultPolicy;
    final decoded = jsonDecode(rawJson);
    if (decoded is! Map<String, dynamic>) {
      return fallback;
    }
    final intra = decoded['intra'] as Map<String, dynamic>?;
    final inter = decoded['inter'] as Map<String, dynamic>?;
    final international = decoded['international'] as Map<String, dynamic>?;

    return _PenaltyPolicy(
      intraLateFeeMinor:
          (intra?['late_fee_minor'] as num?)?.toInt() ??
          fallback.intraLateFeeMinor,
      intraLateWhenAfterDeparture:
          intra?['late_if_cancelled_at_or_after_departure'] as bool? ??
          fallback.intraLateWhenAfterDeparture,
      interGreaterThanHours:
          (inter?['gt_hours'] as num?)?.toInt() ??
          fallback.interGreaterThanHours,
      interGreaterThanHoursPercent:
          (inter?['gt_hours_percent'] as num?)?.toInt() ??
          fallback.interGreaterThanHoursPercent,
      interLessOrEqualHoursPercent:
          (inter?['lte_hours_percent'] as num?)?.toInt() ??
          fallback.interLessOrEqualHoursPercent,
      internationalLessThanHours:
          (international?['lt_hours'] as num?)?.toInt() ??
          fallback.internationalLessThanHours,
      internationalLessThanHoursPercent:
          (international?['lt_hours_percent'] as num?)?.toInt() ??
          fallback.internationalLessThanHoursPercent,
      internationalGreaterOrEqualHoursPercent:
          (international?['gte_hours_percent'] as num?)?.toInt() ??
          fallback.internationalGreaterOrEqualHoursPercent,
    );
  }
}
