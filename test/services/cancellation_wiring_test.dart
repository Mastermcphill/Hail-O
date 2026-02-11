import 'package:flutter_test/flutter_test.dart';
import 'package:hail_o_finance_core/data/sqlite/hailo_database.dart';
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
}
