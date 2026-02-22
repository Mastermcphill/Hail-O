import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:hail_o_finance_core/data/sqlite/hailo_database.dart';
import 'package:hail_o_finance_core/domain/errors/domain_errors.dart';
import 'package:hail_o_finance_core/domain/models/ride_event_type.dart';
import 'package:hail_o_finance_core/domain/services/ledger_invariant_service.dart';
import 'package:hail_o_finance_core/domain/services/operation_journal_service.dart';
import 'package:hail_o_finance_core/domain/services/operation_recovery_service.dart';
import 'package:hail_o_finance_core/domain/services/ride_orchestrator_service.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  test(
    'crash after journal+event insert recovers to exactly-once side effects',
    () async {
      final now = DateTime.utc(2026, 2, 12, 10, 0);
      final db = await HailODatabase().open(databasePath: inMemoryDatabasePath);
      addTearDown(db.close);

      await _seedRide(
        db,
        now: now,
        rideId: 'ride_crash',
        riderId: 'rider_crash',
        driverId: 'driver_crash',
      );

      var injected = false;
      final crashingOrchestrator = RideOrchestratorService(
        db,
        nowUtc: () => now,
        faultHookAfterEventInsert: (eventType) {
          if (!injected && eventType == RideEventType.rideCancelled) {
            injected = true;
            throw const DomainInvariantError(code: 'injected_crash');
          }
        },
      );

      await expectLater(
        crashingOrchestrator.applyEvent(
          eventType: RideEventType.rideCancelled,
          rideId: 'ride_crash',
          idempotencyKey: 'crash_cancel_ride_crash',
          actorId: 'rider_crash',
          payload: const <String, Object?>{
            'payer_user_id': 'rider_crash',
            'penalty_minor': 0,
            'rule_code': 'crash_recovery_cancel',
            'ride_type': 'intra',
          },
        ),
        throwsA(isA<DomainInvariantError>()),
      );

      final rideAfterCrash = await db.query(
        'rides',
        columns: const <String>['status'],
        where: 'id = ?',
        whereArgs: const <Object>['ride_crash'],
        limit: 1,
      );
      expect(rideAfterCrash.first['status'], 'accepted');

      final eventRowsAfterCrash = await db.query(
        'ride_events',
        where: 'ride_id = ? AND event_type = ?',
        whereArgs: const <Object>['ride_crash', 'RIDE_CANCELLED'],
      );
      expect(eventRowsAfterCrash.length, 1);

      final journalService = OperationJournalService(db, nowUtc: () => now);
      final journalAfterCrash = await journalService.getByScopeKey(
        idempotencyScope: 'ride_event',
        idempotencyKey: 'crash_cancel_ride_crash',
      );
      expect(journalAfterCrash, isNotNull);
      expect(journalAfterCrash!.status.dbValue, 'FAILED');

      final recovery = OperationRecoveryService(
        db,
        handlers: <String, OperationRecoveryHandler>{
          'CANCEL': (entry) async {
            final payload =
                jsonDecode(entry.metadataJson) as Map<String, dynamic>;
            final result = await RideOrchestratorService(db, nowUtc: () => now)
                .applyEvent(
                  eventType: RideEventType.rideCancelled,
                  rideId: entry.entityId,
                  idempotencyKey: entry.idempotencyKey,
                  actorId: payload['payer_user_id'] as String?,
                  payload: payload.map(
                    (key, value) => MapEntry<String, Object?>(key, value),
                  ),
                );
            return result['ok'] == true;
          },
        },
      );
      final recoveryResult = await recovery.recover();
      expect(recoveryResult['ok'], true, reason: recoveryResult.toString());
      expect(recoveryResult['committed'], 1);

      final rideAfterRecovery = await db.query(
        'rides',
        columns: const <String>['status'],
        where: 'id = ?',
        whereArgs: const <Object>['ride_crash'],
        limit: 1,
      );
      expect(rideAfterRecovery.first['status'], 'cancelled');

      final penaltyRows = await db.query(
        'penalty_records',
        where: 'ride_id = ?',
        whereArgs: const <Object>['ride_crash'],
      );
      expect(penaltyRows.length, 1);
      expect(penaltyRows.first['amount_minor'], 0);

      final eventRows = await db.query(
        'ride_events',
        where:
            'ride_id = ? AND event_type = ? AND idempotency_scope = ? AND idempotency_key = ?',
        whereArgs: const <Object>[
          'ride_crash',
          'RIDE_CANCELLED',
          'ride_event',
          'crash_cancel_ride_crash',
        ],
      );
      expect(eventRows.length, 1);

      final journalAfterRecovery = await journalService.getByScopeKey(
        idempotencyScope: 'ride_event',
        idempotencyKey: 'crash_cancel_ride_crash',
      );
      expect(journalAfterRecovery, isNotNull);
      expect(journalAfterRecovery!.status.dbValue, 'COMMITTED');

      final invariants = await LedgerInvariantService(db).verifySnapshot();
      expect(invariants['ok'], true, reason: invariants.toString());
    },
  );
}

Future<void> _seedRide(
  Database db, {
  required DateTime now,
  required String rideId,
  required String riderId,
  required String driverId,
}) async {
  final nowIso = now.toIso8601String();
  await db.insert('users', <String, Object?>{
    'id': riderId,
    'role': 'rider',
    'created_at': nowIso,
    'updated_at': nowIso,
  }, conflictAlgorithm: ConflictAlgorithm.ignore);
  await db.insert('users', <String, Object?>{
    'id': driverId,
    'role': 'driver',
    'created_at': nowIso,
    'updated_at': nowIso,
  }, conflictAlgorithm: ConflictAlgorithm.ignore);
  await db.insert('rides', <String, Object?>{
    'id': rideId,
    'rider_id': riderId,
    'driver_id': driverId,
    'trip_scope': 'intra_city',
    'status': 'accepted',
    'bidding_mode': 1,
    'base_fare_minor': 15000,
    'premium_markup_minor': 0,
    'charter_mode': 0,
    'daily_rate_minor': 0,
    'total_fare_minor': 15000,
    'connection_fee_minor': 0,
    'connection_fee_paid': 1,
    'created_at': nowIso,
    'updated_at': nowIso,
  }, conflictAlgorithm: ConflictAlgorithm.replace);
}
