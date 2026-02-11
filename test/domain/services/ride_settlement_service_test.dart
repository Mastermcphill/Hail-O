import 'package:flutter_test/flutter_test.dart';
import 'package:hail_o_finance_core/data/sqlite/hailo_database.dart';
import 'package:hail_o_finance_core/domain/models/wallet.dart';
import 'package:hail_o_finance_core/domain/services/escrow_service.dart';
import 'package:hail_o_finance_core/domain/services/ride_settlement_service.dart';
import 'package:hail_o_finance_core/services/autosave_service.dart';
import 'package:hail_o_finance_core/services/moneybox_service.dart';
import 'package:hail_o_finance_core/services/wallet_scheduler.dart';
import 'package:hail_o_finance_core/services/wallet_service.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  group('Ride settlement on escrow release', () {
    test(
      'manual release settles ride, writes ledgers, payout record, and autosave split',
      () async {
        final now = DateTime.utc(2026, 2, 11, 12, 0);
        final db = await HailODatabase().open(
          databasePath: inMemoryDatabasePath,
        );
        addTearDown(db.close);

        final walletService = WalletService(db, nowUtc: () => now);
        final moneyBoxService = MoneyBoxService(db, nowUtc: () => now);
        final autosaveService = AutosaveService(
          db,
          moneyBoxService: moneyBoxService,
          nowUtc: () => now,
        );
        final settlementService = RideSettlementService(
          db,
          autosaveService: autosaveService,
          nowUtc: () => now,
        );
        final escrowService = EscrowService(
          db,
          rideSettlementService: settlementService,
          nowUtc: () => now,
        );

        await _seedUsersAndRide(
          db,
          now: now,
          riderId: 'rider_happy',
          driverId: 'driver_happy',
          rideId: 'ride_happy',
          escrowId: 'escrow_happy',
          baseFareMinor: 10000,
          premiumMarkupMinor: 0,
          totalFareMinor: 12000,
        );
        await db.insert('seats', <String, Object?>{
          'id': 'seat_happy',
          'ride_id': 'ride_happy',
          'seat_code': 'front_right',
          'seat_type': 'front',
          'base_fare_minor': 10000,
          'markup_minor': 2000,
          'assignment_locked': 1,
          'created_at': now.toIso8601String(),
          'updated_at': now.toIso8601String(),
        });
        await moneyBoxService.ensureAccount(
          ownerId: 'driver_happy',
          tier: 2,
          autosavePercent: 25,
        );

        final released = await escrowService.releaseOnManualOverride(
          escrowId: 'escrow_happy',
          riderId: 'rider_happy',
          idempotencyKey: 'manual_release_happy_1',
        );

        expect(released['released'], true);
        final settlement = released['settlement'] as Map<String, Object?>;
        expect(settlement['ok'], true);
        expect(settlement['commission_gross_minor'], 8000);
        expect(settlement['commission_saved_minor'], 2000);
        expect(settlement['commission_remainder_minor'], 6000);
        expect(settlement['premium_locked_minor'], 1000);

        final walletA = await walletService.getWalletBalanceMinor(
          ownerId: 'driver_happy',
          walletType: WalletType.driverA,
        );
        final walletB = await walletService.getWalletBalanceMinor(
          ownerId: 'driver_happy',
          walletType: WalletType.driverB,
        );
        expect(walletA, 6000);
        expect(walletB, 1000);

        final accountRows = await db.query(
          'moneybox_accounts',
          columns: <String>['principal_minor'],
          where: 'owner_id = ?',
          whereArgs: <Object>['driver_happy'],
          limit: 1,
        );
        expect(accountRows.first['principal_minor'], 2000);

        final payoutRows = await db.query(
          'payout_records',
          where: 'ride_id = ? AND escrow_id = ?',
          whereArgs: <Object>['ride_happy', 'escrow_happy'],
        );
        expect(payoutRows.length, 1);
        expect(payoutRows.first['status'], 'completed');
        expect(payoutRows.first['trigger'], 'manual_override');
      },
    );

    test(
      'release + settlement are idempotent and do not double-credit on replay',
      () async {
        final now = DateTime.utc(2026, 2, 11, 12, 0);
        final db = await HailODatabase().open(
          databasePath: inMemoryDatabasePath,
        );
        addTearDown(db.close);

        final walletService = WalletService(db, nowUtc: () => now);
        final moneyBoxService = MoneyBoxService(db, nowUtc: () => now);
        final autosaveService = AutosaveService(
          db,
          moneyBoxService: moneyBoxService,
          nowUtc: () => now,
        );
        final settlementService = RideSettlementService(
          db,
          autosaveService: autosaveService,
          nowUtc: () => now,
        );
        final escrowService = EscrowService(
          db,
          rideSettlementService: settlementService,
          nowUtc: () => now,
        );

        await _seedUsersAndRide(
          db,
          now: now,
          riderId: 'rider_idem',
          driverId: 'driver_idem',
          rideId: 'ride_idem',
          escrowId: 'escrow_idem',
          baseFareMinor: 10000,
          premiumMarkupMinor: 0,
          totalFareMinor: 10000,
        );
        await moneyBoxService.ensureAccount(
          ownerId: 'driver_idem',
          tier: 2,
          autosavePercent: 10,
        );

        final first = await escrowService.releaseOnManualOverride(
          escrowId: 'escrow_idem',
          riderId: 'rider_idem',
          idempotencyKey: 'manual_release_idem_1',
        );
        final second = await escrowService.releaseOnManualOverride(
          escrowId: 'escrow_idem',
          riderId: 'rider_idem',
          idempotencyKey: 'manual_release_idem_1',
        );

        expect(first['released'], true);
        expect(second['replayed'], true);

        final walletA = await walletService.getWalletBalanceMinor(
          ownerId: 'driver_idem',
          walletType: WalletType.driverA,
        );
        expect(walletA, 7200);

        final walletLedgerRows = await db.query(
          'wallet_ledger',
          where: 'reference_id = ? AND kind = ?',
          whereArgs: <Object>[
            'ride_idem',
            AutosaveService.confirmedCommissionCredit,
          ],
        );
        final payoutRows = await db.query(
          'payout_records',
          where: 'ride_id = ?',
          whereArgs: <Object>['ride_idem'],
        );
        expect(walletLedgerRows.length, 1);
        expect(payoutRows.length, 1);
      },
    );

    test(
      'fleet settlement routes WalletA share to fleet owner and credits driver allowance',
      () async {
        final now = DateTime.utc(2026, 2, 11, 12, 0);
        final db = await HailODatabase().open(
          databasePath: inMemoryDatabasePath,
        );
        addTearDown(db.close);

        final walletService = WalletService(db, nowUtc: () => now);
        final settlementService = RideSettlementService(db, nowUtc: () => now);
        final escrowService = EscrowService(
          db,
          rideSettlementService: settlementService,
          nowUtc: () => now,
        );

        await walletService.upsertUser(
          userId: 'driver_fleet',
          role: 'driver',
          fleetOwnerId: 'fleet_owner_1',
        );
        await walletService.upsertUser(
          userId: 'fleet_owner_1',
          role: 'fleet_owner',
        );
        await walletService.setFleetConfig(
          fleetOwnerId: 'fleet_owner_1',
          allowancePercent: 25,
        );
        await _seedRiderRideAndEscrow(
          db,
          now: now,
          riderId: 'rider_fleet',
          driverId: 'driver_fleet',
          rideId: 'ride_fleet',
          escrowId: 'escrow_fleet',
          baseFareMinor: 20000,
          premiumMarkupMinor: 0,
          totalFareMinor: 20000,
        );

        final released = await escrowService.releaseOnManualOverride(
          escrowId: 'escrow_fleet',
          riderId: 'rider_fleet',
          idempotencyKey: 'manual_release_fleet_1',
        );

        expect(released['released'], true);
        final fleetWallet = await walletService.getWalletBalanceMinor(
          ownerId: 'fleet_owner_1',
          walletType: WalletType.fleetOwner,
        );
        final driverWalletA = await walletService.getWalletBalanceMinor(
          ownerId: 'driver_fleet',
          walletType: WalletType.driverA,
        );
        expect(fleetWallet, 16000);
        expect(driverWalletA, 4000);

        final payoutRows = await db.query(
          'payout_records',
          where: 'ride_id = ?',
          whereArgs: <Object>['ride_fleet'],
          limit: 1,
        );
        expect(payoutRows.first['recipient_owner_id'], 'fleet_owner_1');
        expect(payoutRows.first['driver_allowance_minor'], 4000);
      },
    );

    test(
      'seat premium credit stays in WalletB until Monday unlock job runs',
      () async {
        final now = DateTime.utc(2026, 2, 11, 12, 0);
        final db = await HailODatabase().open(
          databasePath: inMemoryDatabasePath,
        );
        addTearDown(db.close);

        final walletService = WalletService(db, nowUtc: () => now);
        final settlementService = RideSettlementService(db, nowUtc: () => now);
        final escrowService = EscrowService(
          db,
          rideSettlementService: settlementService,
          nowUtc: () => now,
        );
        final scheduler = WalletScheduler(db: db, walletService: walletService);

        await _seedUsersAndRide(
          db,
          now: now,
          riderId: 'rider_markup',
          driverId: 'driver_markup',
          rideId: 'ride_markup',
          escrowId: 'escrow_markup',
          baseFareMinor: 0,
          premiumMarkupMinor: 0,
          totalFareMinor: 6000,
        );
        await db.insert('seats', <String, Object?>{
          'id': 'seat_markup',
          'ride_id': 'ride_markup',
          'seat_code': 'front_right',
          'seat_type': 'front',
          'base_fare_minor': 0,
          'markup_minor': 6000,
          'assignment_locked': 1,
          'created_at': now.toIso8601String(),
          'updated_at': now.toIso8601String(),
        });

        await escrowService.releaseOnManualOverride(
          escrowId: 'escrow_markup',
          riderId: 'rider_markup',
          idempotencyKey: 'manual_release_markup_1',
        );

        final beforeA = await walletService.getWalletBalanceMinor(
          ownerId: 'driver_markup',
          walletType: WalletType.driverA,
        );
        final beforeB = await walletService.getWalletBalanceMinor(
          ownerId: 'driver_markup',
          walletType: WalletType.driverB,
        );
        expect(beforeA, 0);
        expect(beforeB, 3000);

        final schedulerRun = await scheduler.runMondayUnlockMove(
          nowUtc: DateTime.utc(2026, 2, 8, 23, 0),
          idempotencySeed: 'pre_monday_unlock_check',
        );
        expect(schedulerRun['skipped'], true);

        final afterA = await walletService.getWalletBalanceMinor(
          ownerId: 'driver_markup',
          walletType: WalletType.driverA,
        );
        final afterB = await walletService.getWalletBalanceMinor(
          ownerId: 'driver_markup',
          walletType: WalletType.driverB,
        );
        expect(afterA, 0);
        expect(afterB, 3000);
      },
    );
  });
}

Future<void> _seedUsersAndRide(
  Database db, {
  required DateTime now,
  required String riderId,
  required String driverId,
  required String rideId,
  required String escrowId,
  required int baseFareMinor,
  required int premiumMarkupMinor,
  required int totalFareMinor,
}) async {
  await _seedRiderRideAndEscrow(
    db,
    now: now,
    riderId: riderId,
    driverId: driverId,
    rideId: rideId,
    escrowId: escrowId,
    baseFareMinor: baseFareMinor,
    premiumMarkupMinor: premiumMarkupMinor,
    totalFareMinor: totalFareMinor,
  );
  await db.insert('users', <String, Object?>{
    'id': driverId,
    'role': 'driver',
    'created_at': now.toIso8601String(),
    'updated_at': now.toIso8601String(),
  }, conflictAlgorithm: ConflictAlgorithm.ignore);
}

Future<void> _seedRiderRideAndEscrow(
  Database db, {
  required DateTime now,
  required String riderId,
  required String driverId,
  required String rideId,
  required String escrowId,
  required int baseFareMinor,
  required int premiumMarkupMinor,
  required int totalFareMinor,
}) async {
  await db.insert('users', <String, Object?>{
    'id': riderId,
    'role': 'rider',
    'created_at': now.toIso8601String(),
    'updated_at': now.toIso8601String(),
  }, conflictAlgorithm: ConflictAlgorithm.ignore);

  await db.insert('users', <String, Object?>{
    'id': driverId,
    'role': 'driver',
    'created_at': now.toIso8601String(),
    'updated_at': now.toIso8601String(),
  }, conflictAlgorithm: ConflictAlgorithm.ignore);

  await db.insert('rides', <String, Object?>{
    'id': rideId,
    'rider_id': riderId,
    'driver_id': driverId,
    'trip_scope': 'intra_city',
    'status': 'in_progress',
    'bidding_mode': 1,
    'base_fare_minor': baseFareMinor,
    'premium_markup_minor': premiumMarkupMinor,
    'charter_mode': 0,
    'daily_rate_minor': 0,
    'total_fare_minor': totalFareMinor,
    'connection_fee_minor': 0,
    'connection_fee_paid': 0,
    'created_at': now.toIso8601String(),
    'updated_at': now.toIso8601String(),
  }, conflictAlgorithm: ConflictAlgorithm.replace);

  await db.insert('escrow_holds', <String, Object?>{
    'id': escrowId,
    'ride_id': rideId,
    'holder_user_id': riderId,
    'amount_minor': totalFareMinor,
    'status': 'held',
    'created_at': now.toIso8601String(),
  }, conflictAlgorithm: ConflictAlgorithm.replace);
}
