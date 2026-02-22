import 'package:flutter_test/flutter_test.dart';
import 'package:hail_o_finance_core/domain/services/pricing_engine_service.dart';
import 'package:hail_o_finance_core/domain/services/ride_settlement_service.dart';
import 'package:sqflite/sqflite.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'fixtures/old_state_fixture_builder.dart';

void main() {
  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  final boundaries = <String, int>{
    'before_m0013': 12,
    'before_m0014': 13,
    'before_m0015': 14,
  };

  for (final entry in boundaries.entries) {
    test(
      'migration torture upgrade from ${entry.key} remains functional',
      () async {
        final now = DateTime.utc(2026, 2, 12, 12, 0);
        final db = await openDatabaseAtVersion(maxVersion: entry.value);
        addTearDown(db.close);

        await seedLegacyRideState(
          db: db,
          nowUtc: now,
          rideId: 'ride_${entry.key}_records',
          escrowId: 'escrow_${entry.key}_records',
          riderId: 'rider_${entry.key}',
          driverId: 'driver_${entry.key}',
          includePenaltyRecord: true,
          includeLegacyPenalty: true,
        );
        await seedLegacyRideState(
          db: db,
          nowUtc: now.add(const Duration(minutes: 1)),
          rideId: 'ride_${entry.key}_legacy',
          escrowId: 'escrow_${entry.key}_legacy',
          riderId: 'rider_legacy_${entry.key}',
          driverId: 'driver_legacy_${entry.key}',
          includePenaltyRecord: false,
          includeLegacyPenalty: true,
        );

        await upgradeDatabaseToHead(db);

        final settlementService = RideSettlementService(db, nowUtc: () => now);

        final preferRecord = await settlementService.settleOnEscrowRelease(
          escrowId: 'escrow_${entry.key}_records',
          rideId: 'ride_${entry.key}_records',
          idempotencyKey: 'settle:${entry.key}:records',
          trigger: SettlementTrigger.manualOverride,
        );
        final fallbackLegacy = await settlementService.settleOnEscrowRelease(
          escrowId: 'escrow_${entry.key}_legacy',
          rideId: 'ride_${entry.key}_legacy',
          idempotencyKey: 'settle:${entry.key}:legacy',
          trigger: SettlementTrigger.manualOverride,
        );

        expect(preferRecord.ok, true);
        expect(preferRecord.penaltyDueMinor, 2500);
        expect(fallbackLegacy.ok, true);
        expect(fallbackLegacy.penaltyDueMinor, 9000);

        final rideColumns = await db.rawQuery("PRAGMA table_info('rides')");
        final columnNames = rideColumns
            .map((row) => row['name'] as String)
            .toSet();
        expect(columnNames.contains('pricing_version'), true);
        expect(columnNames.contains('pricing_breakdown_json'), true);
        expect(columnNames.contains('quoted_fare_minor'), true);

        final seededPricingRules = Sqflite.firstIntValue(
          await db.rawQuery('SELECT COUNT(*) FROM pricing_rules'),
        )!;
        final seededPenaltyRules = Sqflite.firstIntValue(
          await db.rawQuery('SELECT COUNT(*) FROM penalty_rules'),
        )!;
        final seededComplianceRules = Sqflite.firstIntValue(
          await db.rawQuery('SELECT COUNT(*) FROM compliance_requirements'),
        )!;
        expect(seededPricingRules, greaterThan(0));
        expect(seededPenaltyRules, greaterThan(0));
        expect(seededComplianceRules, greaterThan(0));

        await db.delete('pricing_rules');
        final fallbackEngine = await PricingEngineService.fromDatabase(
          db,
          asOfUtc: now,
          scope: 'intra_city',
        );
        final fallbackQuote = fallbackEngine.quote(
          tripScope: 'intra_city',
          distanceMeters: 8000,
          durationSeconds: 1200,
          luggageCount: 1,
          vehicleClass: PricingVehicleClass.sedan,
          requestedAtUtc: now,
        );
        expect(fallbackQuote.fareMinor, greaterThan(0));
      },
    );
  }
}
