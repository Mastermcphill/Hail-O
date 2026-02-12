import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:hail_o_finance_core/data/sqlite/dao/penalty_rules_dao.dart';
import 'package:hail_o_finance_core/data/sqlite/dao/pricing_rules_dao.dart';
import 'package:hail_o_finance_core/data/sqlite/hailo_database.dart';
import 'package:hail_o_finance_core/domain/models/penalty_rule.dart';
import 'package:hail_o_finance_core/domain/models/pricing_rule.dart';
import 'package:hail_o_finance_core/domain/services/penalty_engine_service.dart';
import 'package:hail_o_finance_core/domain/services/pricing_engine_service.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  test('disabled or invalid rules cannot be force-selected', () async {
    final db = await HailODatabase().open(databasePath: inMemoryDatabasePath);
    addTearDown(db.close);
    final now = DateTime.utc(2026, 2, 12, 14, 0);

    await PricingRulesDao(db).upsert(
      PricingRule(
        version: 'pricing_safe_v1',
        effectiveFrom: DateTime.utc(2025, 1, 1),
        scope: 'tamper_scope',
        parametersJson: jsonEncode(<String, Object?>{
          'base_fare_minor': <String, int>{'intra_city': 1000},
          'distance_rate_per_km_minor': <String, int>{'intra_city': 0},
          'time_rate_per_min_minor': <String, int>{'intra_city': 0},
          'vehicle_multiplier_percent': <String, int>{'sedan': 100},
          'luggage_surcharge_per_extra_minor': 0,
          'surge_windows': <Object?>[],
        }),
        createdAt: now,
      ),
    );
    await PricingRulesDao(db).upsert(
      PricingRule(
        version: 'pricing_tampered_disabled',
        effectiveFrom: DateTime.utc(2025, 2, 1),
        scope: 'tamper_scope',
        parametersJson: '{"base_fare_minor":{"intra_city":99999}}',
        createdAt: now,
        enabled: false,
      ),
    );
    await PricingRulesDao(db).upsert(
      PricingRule(
        version: 'pricing_tampered_invalid',
        effectiveFrom: DateTime.utc(2025, 3, 1),
        scope: 'tamper_scope',
        parametersJson: '{"base_fare_minor":"bad_shape"}',
        createdAt: now,
      ),
    );

    await PenaltyRulesDao(db).upsert(
      PenaltyRule(
        version: 'penalty_safe_v1',
        effectiveFrom: DateTime.utc(2025, 1, 1),
        scope: 'tamper_scope',
        parametersJson: jsonEncode(<String, Object?>{
          'intra': <String, Object?>{
            'late_fee_minor': 10000,
            'late_if_cancelled_at_or_after_departure': true,
          },
          'inter': <String, Object?>{
            'gt_hours': 10,
            'gt_hours_percent': 10,
            'lte_hours_percent': 30,
          },
          'international': <String, Object?>{
            'lt_hours': 24,
            'lt_hours_percent': 50,
            'gte_hours_percent': 0,
          },
        }),
        createdAt: now,
      ),
    );
    await PenaltyRulesDao(db).upsert(
      PenaltyRule(
        version: 'penalty_tampered_invalid',
        effectiveFrom: DateTime.utc(2025, 2, 1),
        scope: 'tamper_scope',
        parametersJson: '{"inter":"bad_shape"}',
        createdAt: now,
      ),
    );

    final pricingEngine = await PricingEngineService.fromDatabase(
      db,
      asOfUtc: now,
      scope: 'tamper_scope',
      subjectId: 'ride_tamper',
    );
    final penaltyEngine = await PenaltyEngineService.fromDatabase(
      db,
      asOfUtc: now,
      scope: 'tamper_scope',
      subjectId: 'ride_tamper',
    );

    expect(pricingEngine.ruleVersion, 'pricing_safe_v1');
    expect(penaltyEngine.ruleVersion, 'penalty_safe_v1');
  });
}
