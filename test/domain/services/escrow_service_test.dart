import 'package:flutter_test/flutter_test.dart';
import 'package:hail_o_finance_core/data/sqlite/hailo_database.dart';
import 'package:hail_o_finance_core/domain/models/latlng.dart';
import 'package:hail_o_finance_core/domain/models/wallet.dart';
import 'package:hail_o_finance_core/domain/services/escrow_service.dart';
import 'package:hail_o_finance_core/services/wallet_service.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  test('escrow releases only on geofence arrival or manual override', () async {
    final db = await HailODatabase().open(databasePath: inMemoryDatabasePath);
    addTearDown(db.close);
    final now = DateTime.utc(2026, 2, 1);
    final service = EscrowService(db, nowUtc: () => now);

    await db.insert('users', <String, Object?>{
      'id': 'rider_escrow',
      'role': 'rider',
      'created_at': now.toIso8601String(),
      'updated_at': now.toIso8601String(),
    });
    await db.insert('rides', <String, Object?>{
      'id': 'ride_escrow_1',
      'rider_id': 'rider_escrow',
      'trip_scope': 'intra_city',
      'status': 'in_progress',
      'bidding_mode': 1,
      'base_fare_minor': 10000,
      'premium_markup_minor': 0,
      'charter_mode': 0,
      'daily_rate_minor': 0,
      'total_fare_minor': 10000,
      'connection_fee_minor': 0,
      'connection_fee_paid': 0,
      'created_at': now.toIso8601String(),
      'updated_at': now.toIso8601String(),
    });
    await db.insert('escrow_holds', <String, Object?>{
      'id': 'escrow_1',
      'ride_id': 'ride_escrow_1',
      'holder_user_id': 'rider_escrow',
      'amount_minor': 10000,
      'status': 'held',
      'created_at': now.toIso8601String(),
    });

    final blocked = await service.releaseOnGeofenceArrival(
      escrowId: 'escrow_1',
      driverPosition: const LatLng(latitude: 6.6000, longitude: 3.4000),
      riderDestination: const LatLng(latitude: 6.5244, longitude: 3.3792),
      idempotencyKey: 'escrow_geofence_fail_1',
      geofenceRadiusMeters: 100,
    );
    expect(blocked['released'], false);

    final manual = await service.releaseOnManualOverride(
      escrowId: 'escrow_1',
      riderId: 'rider_escrow',
      idempotencyKey: 'escrow_manual_ok_1',
    );
    expect(manual['released'], true);
    expect(manual['release_mode'], 'manual_override');
  });

  test(
    'settlement across manual and geofence entrypoints with different keys settles once',
    () async {
      final db = await HailODatabase().open(databasePath: inMemoryDatabasePath);
      addTearDown(db.close);
      final now = DateTime.utc(2026, 2, 1, 10);
      final service = EscrowService(db, nowUtc: () => now);
      final walletService = WalletService(db, nowUtc: () => now);

      await db.insert('users', <String, Object?>{
        'id': 'rider_escrow_settle',
        'role': 'rider',
        'created_at': now.toIso8601String(),
        'updated_at': now.toIso8601String(),
      });
      await db.insert('users', <String, Object?>{
        'id': 'driver_escrow_settle',
        'role': 'driver',
        'created_at': now.toIso8601String(),
        'updated_at': now.toIso8601String(),
      });
      await db.insert('rides', <String, Object?>{
        'id': 'ride_escrow_settle_1',
        'rider_id': 'rider_escrow_settle',
        'driver_id': 'driver_escrow_settle',
        'trip_scope': 'intra_city',
        'status': 'in_progress',
        'bidding_mode': 1,
        'base_fare_minor': 10000,
        'premium_markup_minor': 0,
        'charter_mode': 0,
        'daily_rate_minor': 0,
        'total_fare_minor': 10000,
        'connection_fee_minor': 0,
        'connection_fee_paid': 0,
        'created_at': now.toIso8601String(),
        'updated_at': now.toIso8601String(),
      });
      await db.insert('escrow_holds', <String, Object?>{
        'id': 'escrow_settle_1',
        'ride_id': 'ride_escrow_settle_1',
        'holder_user_id': 'rider_escrow_settle',
        'amount_minor': 10000,
        'status': 'held',
        'created_at': now.toIso8601String(),
      });

      final manual = await service.releaseOnManualOverride(
        escrowId: 'escrow_settle_1',
        riderId: 'rider_escrow_settle',
        idempotencyKey: 'manual_release_settle_1',
        settlementIdempotencyKey: 'settlement_key_manual',
      );
      expect(manual['released'], true);

      final geofenceReplay = await service.releaseOnGeofenceArrival(
        escrowId: 'escrow_settle_1',
        driverPosition: const LatLng(latitude: 6.5244, longitude: 3.3792),
        riderDestination: const LatLng(latitude: 6.5244, longitude: 3.3792),
        idempotencyKey: 'geofence_release_settle_1',
        settlementIdempotencyKey: 'settlement_key_geofence',
      );
      expect(geofenceReplay['ok'], true);
      expect(geofenceReplay['released'], false);
      expect(geofenceReplay['status'], 'released');

      final payoutRows = await db.query(
        'payout_records',
        where: 'escrow_id = ?',
        whereArgs: const <Object>['escrow_settle_1'],
      );
      expect(payoutRows.length, 1);

      final settlementMap =
          geofenceReplay['settlement'] as Map<String, Object?>;
      expect(settlementMap['ok'], true);
      expect(settlementMap['replayed'], true);

      final walletA = await walletService.getWalletBalanceMinor(
        ownerId: 'driver_escrow_settle',
        walletType: WalletType.driverA,
      );
      expect(walletA, 8000);

      final commissionCreditRows = await db.query(
        'wallet_ledger',
        where: 'reference_id = ? AND kind = ?',
        whereArgs: const <Object>[
          'ride_escrow_settle_1',
          'confirmed_commission_credit',
        ],
      );
      expect(commissionCreditRows.length, 1);
    },
  );
}
