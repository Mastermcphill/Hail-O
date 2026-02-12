import 'dart:convert';

import 'package:sqflite/sqflite.dart';

import '../../data/sqlite/dao/pricing_rules_dao.dart';
import '../models/pricing_quote.dart';
import 'rule_rollout_service.dart';
import 'rule_validation_service.dart';

enum PricingVehicleClass {
  sedan('sedan'),
  hatchback('hatchback'),
  suv('suv'),
  bus('bus');

  const PricingVehicleClass(this.dbValue);
  final String dbValue;

  static PricingVehicleClass fromDbValue(String value) {
    return PricingVehicleClass.values.firstWhere(
      (vehicleClass) => vehicleClass.dbValue == value,
      orElse: () => PricingVehicleClass.sedan,
    );
  }
}

class PricingEngineService {
  const PricingEngineService({this.ruleVersion = 'pricing_v1'})
    : _policy = _PricingPolicy.defaultPolicy;

  static Future<PricingEngineService> fromDatabase(
    DatabaseExecutor db, {
    required DateTime asOfUtc,
    String scope = 'default',
    String? subjectId,
    RuleRolloutService rolloutService = const RuleRolloutService(),
    RuleValidationService validationService = const RuleValidationService(),
  }) async {
    final rules = await PricingRulesDao(
      db,
    ).listActiveRules(asOfUtc: asOfUtc, scope: scope);
    if (rules.isEmpty) {
      return PricingEngineService();
    }
    for (final rule in rules) {
      final validation = validationService.validatePricingRuleJson(
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
      return PricingEngineService._(
        ruleVersion: rule.version,
        policy: _PricingPolicy.fromJson(rule.parametersJson),
      );
    }
    // No eligible/valid rule matched rollout. Fall back to deterministic default.
    // This keeps booking deterministic while avoiding invalid/tampered rule rows.
    return PricingEngineService();
  }

  const PricingEngineService._({
    required this.ruleVersion,
    required _PricingPolicy policy,
  }) : _policy = policy;

  final String ruleVersion;
  final _PricingPolicy _policy;

  PricingQuote quote({
    required String tripScope,
    required int distanceMeters,
    required int durationSeconds,
    required int luggageCount,
    required PricingVehicleClass vehicleClass,
    required DateTime requestedAtUtc,
  }) {
    final scope = tripScope.trim().toLowerCase();
    final distanceKm = distanceMeters < 0 ? 0 : distanceMeters ~/ 1000;
    final durationMinutes = durationSeconds < 0 ? 0 : durationSeconds ~/ 60;

    final baseFareMinor = _baseFareMinor(scope);
    final distanceComponentMinor = distanceKm * _distanceRatePerKmMinor(scope);
    final timeComponentMinor = durationMinutes * _timeRatePerMinuteMinor(scope);
    final luggageSurchargeMinor = luggageCount > 2
        ? (luggageCount - 2) * _policy.luggageSurchargePerExtraMinor
        : 0;

    var subtotalMinor =
        baseFareMinor +
        distanceComponentMinor +
        timeComponentMinor +
        luggageSurchargeMinor;
    subtotalMinor = _applyVehicleMultiplier(subtotalMinor, vehicleClass);
    final surgePercent = _surgePercentForTime(requestedAtUtc.toUtc());
    final surgeMinor = (subtotalMinor * surgePercent) ~/ 100;
    final fareMinor = subtotalMinor + surgeMinor;

    final breakdown = <String, Object?>{
      'rule_version': ruleVersion,
      'trip_scope': scope,
      'distance_meters': distanceMeters,
      'duration_seconds': durationSeconds,
      'distance_km_rounded': distanceKm,
      'duration_min_rounded': durationMinutes,
      'vehicle_class': vehicleClass.dbValue,
      'base_fare_minor': baseFareMinor,
      'distance_component_minor': distanceComponentMinor,
      'time_component_minor': timeComponentMinor,
      'luggage_surcharge_minor': luggageSurchargeMinor,
      'surge_percent': surgePercent,
      'surge_minor': surgeMinor,
      'fare_minor': fareMinor,
    };

    return PricingQuote(
      fareMinor: fareMinor,
      ruleVersion: ruleVersion,
      breakdownJson: jsonEncode(breakdown),
    );
  }

  int _baseFareMinor(String scope) {
    return _policy.baseFareMinorByScope[scope] ??
        _policy.baseFareMinorByScope['intra_city'] ??
        15000;
  }

  int _distanceRatePerKmMinor(String scope) {
    return _policy.distanceRatePerKmMinorByScope[scope] ??
        _policy.distanceRatePerKmMinorByScope['intra_city'] ??
        2000;
  }

  int _timeRatePerMinuteMinor(String scope) {
    return _policy.timeRatePerMinuteMinorByScope[scope] ??
        _policy.timeRatePerMinuteMinorByScope['intra_city'] ??
        150;
  }

  int _applyVehicleMultiplier(
    int subtotalMinor,
    PricingVehicleClass vehicleClass,
  ) {
    final percent =
        _policy.vehicleMultiplierPercentByClass[vehicleClass.dbValue] ?? 100;
    return (subtotalMinor * percent) ~/ 100;
  }

  int _surgePercentForTime(DateTime requestedAtUtc) {
    final hour = requestedAtUtc.hour;
    for (final window in _policy.surgeWindows) {
      if (hour >= window.fromHour && hour <= window.toHour) {
        return window.percent;
      }
    }
    return 0;
  }
}

class _PricingPolicy {
  const _PricingPolicy({
    required this.baseFareMinorByScope,
    required this.distanceRatePerKmMinorByScope,
    required this.timeRatePerMinuteMinorByScope,
    required this.vehicleMultiplierPercentByClass,
    required this.luggageSurchargePerExtraMinor,
    required this.surgeWindows,
  });

  final Map<String, int> baseFareMinorByScope;
  final Map<String, int> distanceRatePerKmMinorByScope;
  final Map<String, int> timeRatePerMinuteMinorByScope;
  final Map<String, int> vehicleMultiplierPercentByClass;
  final int luggageSurchargePerExtraMinor;
  final List<_SurgeWindow> surgeWindows;

  static const _PricingPolicy defaultPolicy = _PricingPolicy(
    baseFareMinorByScope: <String, int>{
      'intra_city': 15000,
      'inter_state': 40000,
      'cross_country': 70000,
      'international': 120000,
    },
    distanceRatePerKmMinorByScope: <String, int>{
      'intra_city': 2000,
      'inter_state': 5000,
      'cross_country': 7000,
      'international': 9000,
    },
    timeRatePerMinuteMinorByScope: <String, int>{
      'intra_city': 150,
      'inter_state': 300,
      'cross_country': 400,
      'international': 500,
    },
    vehicleMultiplierPercentByClass: <String, int>{
      'sedan': 100,
      'hatchback': 95,
      'suv': 120,
      'bus': 150,
    },
    luggageSurchargePerExtraMinor: 2000,
    surgeWindows: <_SurgeWindow>[
      _SurgeWindow(fromHour: 7, toHour: 10, percent: 10),
      _SurgeWindow(fromHour: 17, toHour: 20, percent: 10),
    ],
  );

  factory _PricingPolicy.defaults() {
    return defaultPolicy;
  }

  factory _PricingPolicy.fromJson(String rawJson) {
    final fallback = _PricingPolicy.defaults();
    final decoded = jsonDecode(rawJson);
    if (decoded is! Map<String, dynamic>) {
      return fallback;
    }

    Map<String, int> mapFrom(String key, Map<String, int> defaultValue) {
      final raw = decoded[key];
      if (raw is! Map) {
        return defaultValue;
      }
      final out = <String, int>{};
      for (final entry in raw.entries) {
        final value = entry.value;
        if (value is num) {
          out[entry.key.toString().toLowerCase()] = value.toInt();
        }
      }
      return out.isEmpty ? defaultValue : out;
    }

    final rawWindows = decoded['surge_windows'];
    var windows = fallback.surgeWindows;
    if (rawWindows is List) {
      final parsed = <_SurgeWindow>[];
      for (final dynamic window in rawWindows) {
        if (window is Map<String, dynamic>) {
          final fromHour = (window['from_hour'] as num?)?.toInt();
          final toHour = (window['to_hour'] as num?)?.toInt();
          final percent = (window['percent'] as num?)?.toInt();
          if (fromHour != null && toHour != null && percent != null) {
            parsed.add(
              _SurgeWindow(
                fromHour: fromHour,
                toHour: toHour,
                percent: percent,
              ),
            );
          }
        }
      }
      if (parsed.isNotEmpty) {
        windows = parsed;
      }
    }

    return _PricingPolicy(
      baseFareMinorByScope: mapFrom(
        'base_fare_minor',
        fallback.baseFareMinorByScope,
      ),
      distanceRatePerKmMinorByScope: mapFrom(
        'distance_rate_per_km_minor',
        fallback.distanceRatePerKmMinorByScope,
      ),
      timeRatePerMinuteMinorByScope: mapFrom(
        'time_rate_per_min_minor',
        fallback.timeRatePerMinuteMinorByScope,
      ),
      vehicleMultiplierPercentByClass: mapFrom(
        'vehicle_multiplier_percent',
        fallback.vehicleMultiplierPercentByClass,
      ),
      luggageSurchargePerExtraMinor:
          (decoded['luggage_surcharge_per_extra_minor'] as num?)?.toInt() ??
          fallback.luggageSurchargePerExtraMinor,
      surgeWindows: windows,
    );
  }
}

class _SurgeWindow {
  const _SurgeWindow({
    required this.fromHour,
    required this.toHour,
    required this.percent,
  });

  final int fromHour;
  final int toHour;
  final int percent;
}
