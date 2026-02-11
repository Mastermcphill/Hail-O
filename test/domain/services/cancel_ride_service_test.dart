import 'package:flutter_test/flutter_test.dart';
import 'package:hail_o_finance_core/data/sqlite/hailo_database.dart';
import 'package:hail_o_finance_core/domain/services/cancel_ride_service.dart';
import 'package:hail_o_finance_core/domain/services/penalty_engine_service.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  test(
    'cancellation collection writes records + ledgers and is idempotent',
    () async {
      final now = DateTime.utc(2026, 3, 3, 9);
      final db = await HailODatabase().open(databasePath: inMemoryDatabasePath);
      addTearDown(db.close);
      final service = CancelRideService(db, nowUtc: () => now);

      await db.insert('users', <String, Object?>{
        'id': 'payer_user_1',
        'role': 'driver',
        'created_at': now.toIso8601String(),
        'updated_at': now.toIso8601String(),
      });
      await db.insert('users', <String, Object?>{
        'id': 'rider_cancel_1',
        'role': 'rider',
        'created_at': now.toIso8601String(),
        'updated_at': now.toIso8601String(),
      });
      await db.insert('rides', <String, Object?>{
        'id': 'ride_cancel_1',
        'rider_id': 'rider_cancel_1',
        'trip_scope': 'inter_state',
        'status': 'accepted',
        'bidding_mode': 1,
        'base_fare_minor': 100000,
        'premium_markup_minor': 0,
        'charter_mode': 0,
        'daily_rate_minor': 0,
        'total_fare_minor': 100000,
        'connection_fee_minor': 0,
        'connection_fee_paid': 0,
        'created_at': now.toIso8601String(),
        'updated_at': now.toIso8601String(),
      });
      await db.insert('wallets', <String, Object?>{
        'owner_id': 'payer_user_1',
        'wallet_type': 'driver_a',
        'balance_minor': 100000,
        'reserved_minor': 0,
        'currency': 'NGN',
        'updated_at': now.toIso8601String(),
        'created_at': now.toIso8601String(),
      });

      final first = await service.cancelRideAndCollectPenalty(
        rideId: 'ride_cancel_1',
        payerUserId: 'payer_user_1',
        rideType: RideType.inter,
        totalFareMinor: 100000,
        scheduledDeparture: DateTime.utc(2026, 3, 3, 18),
        cancelledAt: now,
        idempotencyKey: 'cancel_penalty_1',
      );

      expect(first.ok, true);
      expect(first.penaltyMinor, 30000);
      expect(first.status, 'collected');
      expect(first.replayed, false);

      final second = await service.cancelRideAndCollectPenalty(
        rideId: 'ride_cancel_1',
        payerUserId: 'payer_user_1',
        rideType: RideType.inter,
        totalFareMinor: 100000,
        scheduledDeparture: DateTime.utc(2026, 3, 3, 18),
        cancelledAt: now,
        idempotencyKey: 'cancel_penalty_1',
      );

      expect(second.ok, true);
      expect(second.replayed, true);
      expect(second.penaltyMinor, 30000);

      final penaltyRows = await db.query(
        'penalty_records',
        where: 'idempotency_scope = ? AND idempotency_key = ?',
        whereArgs: const <Object>['cancellation_penalty', 'cancel_penalty_1'],
      );
      expect(penaltyRows.length, 1);
      expect(penaltyRows.first['amount_minor'], 30000);
      expect(penaltyRows.first['status'], 'collected');

      final ledgerRows = await db.query(
        'wallet_ledger',
        where: 'idempotency_scope = ?',
        whereArgs: const <Object>['cancellation_penalty'],
      );
      expect(ledgerRows.length, 2);

      final payerWallet = await db.query(
        'wallets',
        where: 'owner_id = ? AND wallet_type = ?',
        whereArgs: const <Object>['payer_user_1', 'driver_a'],
        limit: 1,
      );
      expect(payerWallet.first['balance_minor'], 70000);

      final platformWallet = await db.query(
        'wallets',
        where: 'owner_id = ? AND wallet_type = ?',
        whereArgs: const <Object>['platform', 'platform'],
        limit: 1,
      );
      expect(platformWallet.first['balance_minor'], 30000);
    },
  );

  test(
    'already-cancelled ride with a new key does not double-charge',
    () async {
      final now = DateTime.utc(2026, 3, 3, 9);
      final db = await HailODatabase().open(databasePath: inMemoryDatabasePath);
      addTearDown(db.close);
      final service = CancelRideService(db, nowUtc: () => now);

      await db.insert('users', <String, Object?>{
        'id': 'payer_user_2',
        'role': 'driver',
        'created_at': now.toIso8601String(),
        'updated_at': now.toIso8601String(),
      });
      await db.insert('users', <String, Object?>{
        'id': 'rider_cancel_2',
        'role': 'rider',
        'created_at': now.toIso8601String(),
        'updated_at': now.toIso8601String(),
      });
      await db.insert('rides', <String, Object?>{
        'id': 'ride_cancel_2',
        'rider_id': 'rider_cancel_2',
        'driver_id': 'payer_user_2',
        'trip_scope': 'inter_state',
        'status': 'accepted',
        'bidding_mode': 1,
        'base_fare_minor': 100000,
        'premium_markup_minor': 0,
        'charter_mode': 0,
        'daily_rate_minor': 0,
        'total_fare_minor': 100000,
        'connection_fee_minor': 0,
        'connection_fee_paid': 0,
        'created_at': now.toIso8601String(),
        'updated_at': now.toIso8601String(),
      });
      await db.insert('wallets', <String, Object?>{
        'owner_id': 'payer_user_2',
        'wallet_type': 'driver_a',
        'balance_minor': 100000,
        'reserved_minor': 0,
        'currency': 'NGN',
        'updated_at': now.toIso8601String(),
        'created_at': now.toIso8601String(),
      });

      final first = await service.cancelRideAndCollectPenalty(
        rideId: 'ride_cancel_2',
        payerUserId: 'payer_user_2',
        rideType: RideType.inter,
        totalFareMinor: 100000,
        scheduledDeparture: DateTime.utc(2026, 3, 3, 18),
        cancelledAt: now,
        idempotencyKey: 'cancel_penalty_2',
      );
      expect(first.ok, true);
      expect(first.replayed, false);

      final second = await service.collectCancellationPenalty(
        rideId: 'ride_cancel_2',
        payerUserId: 'payer_user_2',
        penaltyMinor: 30000,
        idempotencyKey: 'cancel_penalty_2_new_key',
        ruleCode: 'manual_retrigger',
      );
      expect(second.ok, true);
      expect(second.replayed, true);
      expect(second.penaltyMinor, 30000);

      final penaltyRows = await db.query(
        'penalty_records',
        where: 'ride_id = ?',
        whereArgs: const <Object>['ride_cancel_2'],
      );
      expect(penaltyRows.length, 1);
      final ledgerRows = await db.query(
        'wallet_ledger',
        where: 'idempotency_scope = ?',
        whereArgs: const <Object>['cancellation_penalty'],
      );
      expect(ledgerRows.length, 2);
    },
  );
}
