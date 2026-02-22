import 'package:flutter_test/flutter_test.dart';
import 'package:hail_o_finance_core/data/sqlite/hailo_database.dart';
import 'package:hail_o_finance_core/domain/services/cancel_ride_service.dart';
import 'package:hail_o_finance_core/domain/services/penalty_engine_service.dart';
import 'package:hail_o_finance_core/services/wallet_service.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  test(
    'payConnectionFee timeout routes cancellation through penalty records',
    () async {
      final db = await HailODatabase().open(databasePath: inMemoryDatabasePath);
      addTearDown(db.close);

      final openedAt = DateTime.utc(2026, 3, 7, 8, 0);
      await db.insert('users', <String, Object?>{
        'id': 'rider_timeout_1',
        'role': 'rider',
        'created_at': openedAt.toIso8601String(),
        'updated_at': openedAt.toIso8601String(),
      });
      await db.insert('next_of_kin', <String, Object?>{
        'user_id': 'rider_timeout_1',
        'full_name': 'Timeout Kin',
        'phone': '+234111111111',
        'relationship': 'family',
        'created_at': openedAt.toIso8601String(),
        'updated_at': openedAt.toIso8601String(),
      });
      final openService = WalletService(db, nowUtc: () => openedAt);
      await openService.openBidConnectionFeePaywall(
        rideId: 'ride_timeout_1',
        riderId: 'rider_timeout_1',
        driverId: 'driver_timeout_1',
        tripScope: 'intra_city',
        idempotencyKey: 'connection_lock_1',
      );

      final payAfterDeadline = WalletService(
        db,
        nowUtc: () => openedAt.add(const Duration(minutes: 11)),
      );
      final result = await payAfterDeadline.payConnectionFee(
        rideId: 'ride_timeout_1',
        idempotencyKey: 'connection_pay_1',
      );

      expect(result['ok'], false);
      expect(result['error'], 'connection_fee_timeout_auto_cancelled');

      final rideRows = await db.query(
        'rides',
        where: 'id = ?',
        whereArgs: const <Object>['ride_timeout_1'],
        limit: 1,
      );
      expect(rideRows.first['status'], 'cancelled');

      final penaltyRows = await db.query(
        'penalty_records',
        where: 'ride_id = ?',
        whereArgs: const <Object>['ride_timeout_1'],
      );
      expect(penaltyRows.length, 1);
      expect(penaltyRows.first['amount_minor'], 0);
      expect(
        penaltyRows.first['rule_code'],
        'connection_fee_timeout_auto_cancelled',
      );
      expect(penaltyRows.first['idempotency_scope'], 'cancellation_penalty');
      expect(
        penaltyRows.first['idempotency_key'],
        'connection_fee_timeout:ride_timeout_1',
      );
    },
  );

  test(
    'autoCancelUnpaidConnectionFees routes each cancellation through penalty records',
    () async {
      final db = await HailODatabase().open(databasePath: inMemoryDatabasePath);
      addTearDown(db.close);

      final openedAt = DateTime.utc(2026, 3, 7, 8, 0);
      await db.insert('users', <String, Object?>{
        'id': 'rider_auto_cancel_1',
        'role': 'rider',
        'created_at': openedAt.toIso8601String(),
        'updated_at': openedAt.toIso8601String(),
      });
      await db.insert('next_of_kin', <String, Object?>{
        'user_id': 'rider_auto_cancel_1',
        'full_name': 'Auto Kin One',
        'phone': '+234111111112',
        'relationship': 'family',
        'created_at': openedAt.toIso8601String(),
        'updated_at': openedAt.toIso8601String(),
      });
      await db.insert('users', <String, Object?>{
        'id': 'rider_auto_cancel_2',
        'role': 'rider',
        'created_at': openedAt.toIso8601String(),
        'updated_at': openedAt.toIso8601String(),
      });
      await db.insert('next_of_kin', <String, Object?>{
        'user_id': 'rider_auto_cancel_2',
        'full_name': 'Auto Kin Two',
        'phone': '+234111111113',
        'relationship': 'family',
        'created_at': openedAt.toIso8601String(),
        'updated_at': openedAt.toIso8601String(),
      });
      final openService = WalletService(db, nowUtc: () => openedAt);
      await openService.openBidConnectionFeePaywall(
        rideId: 'ride_auto_cancel_1',
        riderId: 'rider_auto_cancel_1',
        driverId: 'driver_auto_cancel_1',
        tripScope: 'inter_state',
        idempotencyKey: 'connection_lock_2',
      );
      await openService.openBidConnectionFeePaywall(
        rideId: 'ride_auto_cancel_2',
        riderId: 'rider_auto_cancel_2',
        driverId: 'driver_auto_cancel_2',
        tripScope: 'intra_city',
        idempotencyKey: 'connection_lock_3',
      );

      final sweepService = WalletService(
        db,
        nowUtc: () => openedAt.add(const Duration(minutes: 11)),
      );
      final cancelled = await sweepService.autoCancelUnpaidConnectionFees(
        idempotencyKey: 'auto_cancel_batch_1',
      );
      expect(cancelled, 2);

      final replay = await sweepService.autoCancelUnpaidConnectionFees(
        idempotencyKey: 'auto_cancel_batch_1',
      );
      expect(replay, 0);

      final cancelledRides = await db.query(
        'rides',
        where: 'id IN (?, ?) AND status = ?',
        whereArgs: const <Object>[
          'ride_auto_cancel_1',
          'ride_auto_cancel_2',
          'cancelled',
        ],
      );
      expect(cancelledRides.length, 2);

      final penaltyRows = await db.query(
        'penalty_records',
        where: 'rule_code = ?',
        whereArgs: const <Object>['connection_fee_timeout_auto_cancelled'],
        orderBy: 'ride_id ASC',
      );
      expect(penaltyRows.length, 2);
      expect(
        penaltyRows[0]['idempotency_key'],
        'connection_fee_auto_cancel:ride_auto_cancel_1',
      );
      expect(
        penaltyRows[1]['idempotency_key'],
        'connection_fee_auto_cancel:ride_auto_cancel_2',
      );
    },
  );

  test(
    'manual cancel flow routes through collectCancellationPenalty and is idempotent',
    () async {
      final db = await HailODatabase().open(databasePath: inMemoryDatabasePath);
      addTearDown(db.close);

      final now = DateTime.utc(2026, 3, 8, 10);
      await db.insert('users', <String, Object?>{
        'id': 'manual_cancel_payer_1',
        'role': 'driver',
        'created_at': now.toIso8601String(),
        'updated_at': now.toIso8601String(),
      });
      await db.insert('users', <String, Object?>{
        'id': 'manual_cancel_rider_1',
        'role': 'rider',
        'created_at': now.toIso8601String(),
        'updated_at': now.toIso8601String(),
      });
      await db.insert('rides', <String, Object?>{
        'id': 'ride_manual_cancel_1',
        'rider_id': 'manual_cancel_rider_1',
        'driver_id': 'manual_cancel_payer_1',
        'trip_scope': 'inter_state',
        'status': 'accepted',
        'bidding_mode': 1,
        'base_fare_minor': 120000,
        'premium_markup_minor': 0,
        'charter_mode': 0,
        'daily_rate_minor': 0,
        'total_fare_minor': 120000,
        'connection_fee_minor': 0,
        'connection_fee_paid': 0,
        'created_at': now.toIso8601String(),
        'updated_at': now.toIso8601String(),
      });
      await db.insert('wallets', <String, Object?>{
        'owner_id': 'manual_cancel_payer_1',
        'wallet_type': 'driver_a',
        'balance_minor': 120000,
        'reserved_minor': 0,
        'currency': 'NGN',
        'updated_at': now.toIso8601String(),
        'created_at': now.toIso8601String(),
      });

      final cancelService = CancelRideService(db, nowUtc: () => now);
      final first = await cancelService.cancelRideAndCollectPenalty(
        rideId: 'ride_manual_cancel_1',
        payerUserId: 'manual_cancel_payer_1',
        rideType: RideType.inter,
        totalFareMinor: 120000,
        scheduledDeparture: now.add(const Duration(hours: 4)),
        cancelledAt: now,
        idempotencyKey: 'manual_cancel_1',
      );
      expect(first.ok, true);
      expect(first.replayed, false);
      expect(first.penaltyMinor, 36000);

      final second = await cancelService.cancelRideAndCollectPenalty(
        rideId: 'ride_manual_cancel_1',
        payerUserId: 'manual_cancel_payer_1',
        rideType: RideType.inter,
        totalFareMinor: 120000,
        scheduledDeparture: now.add(const Duration(hours: 4)),
        cancelledAt: now,
        idempotencyKey: 'manual_cancel_1',
      );
      expect(second.ok, true);
      expect(second.replayed, true);
      expect(second.penaltyMinor, 36000);

      final rideRows = await db.query(
        'rides',
        where: 'id = ?',
        whereArgs: const <Object>['ride_manual_cancel_1'],
        limit: 1,
      );
      expect(rideRows.first['status'], 'cancelled');

      final penaltyRows = await db.query(
        'penalty_records',
        where: 'ride_id = ?',
        whereArgs: const <Object>['ride_manual_cancel_1'],
      );
      expect(penaltyRows.length, 1);
      expect(penaltyRows.first['amount_minor'], 36000);
      expect(penaltyRows.first['idempotency_scope'], 'cancellation_penalty');
      expect(penaltyRows.first['idempotency_key'], 'manual_cancel_1');

      final ledgerRows = await db.query(
        'wallet_ledger',
        where: 'idempotency_scope = ?',
        whereArgs: const <Object>['cancellation_penalty'],
      );
      expect(ledgerRows.length, 2);
    },
  );
}
