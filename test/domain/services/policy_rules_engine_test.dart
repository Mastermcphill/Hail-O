import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:hail_o_finance_core/data/sqlite/dao/compliance_requirements_dao.dart';
import 'package:hail_o_finance_core/data/sqlite/dao/penalty_rules_dao.dart';
import 'package:hail_o_finance_core/data/sqlite/dao/pricing_rules_dao.dart';
import 'package:hail_o_finance_core/data/sqlite/dao/users_dao.dart';
import 'package:hail_o_finance_core/data/sqlite/hailo_database.dart';
import 'package:hail_o_finance_core/domain/models/compliance_requirement.dart';
import 'package:hail_o_finance_core/domain/models/penalty_rule.dart';
import 'package:hail_o_finance_core/domain/models/pricing_rule.dart';
import 'package:hail_o_finance_core/domain/models/ride_trip.dart';
import 'package:hail_o_finance_core/domain/models/user.dart';
import 'package:hail_o_finance_core/domain/services/compliance_guard_service.dart';
import 'package:hail_o_finance_core/domain/services/penalty_engine_service.dart';
import 'package:hail_o_finance_core/domain/services/pricing_engine_service.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  test(
    'PricingEngineService.fromDatabase selects active scoped rule',
    () async {
      final db = await HailODatabase().open(databasePath: inMemoryDatabasePath);
      addTearDown(db.close);

      final dao = PricingRulesDao(db);
      final now = DateTime.utc(2026, 1, 1, 1, 0);

      await dao.upsert(
        PricingRule(
          version: 'pricing_inter_v9',
          effectiveFrom: DateTime.utc(2025, 12, 1),
          scope: 'inter_state_policy_test',
          parametersJson: jsonEncode(<String, Object?>{
            'base_fare_minor': <String, int>{'inter_state': 100},
            'distance_rate_per_km_minor': <String, int>{'inter_state': 20},
            'time_rate_per_min_minor': <String, int>{'inter_state': 5},
            'vehicle_multiplier_percent': <String, int>{'sedan': 100},
            'luggage_surcharge_per_extra_minor': 0,
            'surge_windows': <Object?>[],
          }),
          createdAt: now,
        ),
      );

      final engine = await PricingEngineService.fromDatabase(
        db,
        asOfUtc: now,
        scope: 'inter_state_policy_test',
      );
      final quote = engine.quote(
        tripScope: TripScope.interState.dbValue,
        distanceMeters: 1000,
        durationSeconds: 60,
        luggageCount: 0,
        vehicleClass: PricingVehicleClass.sedan,
        requestedAtUtc: now,
      );

      expect(engine.ruleVersion, 'pricing_inter_v9');
      expect(quote.fareMinor, 125);
    },
  );

  test(
    'PenaltyEngineService.fromDatabase selects active scoped rule',
    () async {
      final db = await HailODatabase().open(databasePath: inMemoryDatabasePath);
      addTearDown(db.close);

      final dao = PenaltyRulesDao(db);
      final now = DateTime.utc(2026, 1, 1, 0, 0);

      await dao.upsert(
        PenaltyRule(
          version: 'penalty_inter_v9',
          effectiveFrom: DateTime.utc(2025, 12, 1),
          scope: 'inter_policy_test',
          parametersJson: jsonEncode(<String, Object?>{
            'intra': <String, Object?>{
              'late_fee_minor': 50000,
              'late_if_cancelled_at_or_after_departure': true,
            },
            'inter': <String, Object?>{
              'gt_hours': 8,
              'gt_hours_percent': 12,
              'lte_hours_percent': 40,
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

      final engine = await PenaltyEngineService.fromDatabase(
        db,
        asOfUtc: now,
        scope: 'inter_policy_test',
      );

      final result = engine.computeCancellationPenaltyMinor(
        rideType: RideType.inter,
        totalFareMinor: 100000,
        scheduledDeparture: DateTime.utc(2026, 1, 2, 12, 0),
        cancelledAt: DateTime.utc(2026, 1, 2, 1, 0),
      );

      expect(engine.ruleVersion, 'penalty_inter_v9');
      expect(result.penaltyMinor, 12000);
    },
  );

  test(
    'ComplianceGuardService respects compliance_requirements policy rows',
    () async {
      final db = await HailODatabase().open(databasePath: inMemoryDatabasePath);
      addTearDown(db.close);

      final now = DateTime.utc(2026, 1, 1);
      final user = User(
        id: 'rider_policy',
        role: UserRole.rider,
        createdAt: now,
        updatedAt: now,
      );
      await UsersDao(db).insert(user);

      await ComplianceRequirementsDao(db).upsert(
        ComplianceRequirement(
          id: 'cross_country_ng_bj_no_kin_no_docs',
          scope: TripScope.crossCountry.dbValue,
          fromCountry: 'NG',
          toCountry: 'BJ',
          requiredDocsJson: jsonEncode(<String, Object?>{
            'requires_next_of_kin': false,
            'allowed_doc_types': <String>[],
            'requires_verified': true,
            'requires_not_expired': true,
          }),
          createdAt: now,
        ),
      );
      addTearDown(() async {
        await db.delete(
          'compliance_requirements',
          where: 'id = ?',
          whereArgs: <Object>['cross_country_ng_bj_no_kin_no_docs'],
        );
      });

      final guard = ComplianceGuardService(db, nowUtc: () => now);

      await guard.assertEligibleForTrip(
        riderUserId: 'rider_policy',
        tripScope: TripScope.crossCountry,
        originCountry: 'NG',
        destinationCountry: 'BJ',
      );
    },
  );
}
