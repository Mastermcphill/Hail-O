import 'package:flutter_test/flutter_test.dart';
import 'package:hail_o_finance_core/data/sqlite/hailo_database.dart';
import 'package:hail_o_finance_core/services/autosave_service.dart';
import 'package:hail_o_finance_core/services/finance_database.dart';
import 'package:hail_o_finance_core/services/moneybox_service.dart';
import 'package:hail_o_finance_core/services/wallet_scheduler.dart';
import 'package:hail_o_finance_core/services/wallet_service.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  group('Finance Core Rules', () {
    test(
      'Monday unlock move transfers WalletB to WalletA at 00:01 Monday',
      () async {
        final db = await HailODatabase().open(
          databasePath: inMemoryDatabasePath,
        );
        addTearDown(db.close);

        final walletService = WalletService(db);
        final scheduler = WalletScheduler(db: db, walletService: walletService);

        await walletService.upsertUser(userId: 'driver_1', role: 'driver');

        await walletService.settleRideFinance(
          rideId: 'ride_unlock_1',
          driverId: 'driver_1',
          baseFareMinor: 0,
          premiumSeatMarkupMinor: 10000,
          cashCollectedMinor: 0,
          idempotencyKey: 'settle_unlock_1',
        );

        final before = await walletService.getDriverWalletBalances('driver_1');
        expect(before['wallet_b_minor'], 5000);

        final run = await scheduler.runMondayUnlockMove(
          nowUtc: DateTime.utc(2026, 1, 4, 23, 1),
          idempotencySeed: 'monday_unlock_batch',
        );

        expect(run['skipped'], false);
        expect(run['moved_wallet_count'], 1);
        expect(run['moved_total_minor'], 5000);

        final after = await walletService.getDriverWalletBalances('driver_1');
        expect(after['wallet_a_minor'], 5000);
        expect(after['wallet_b_minor'], 0);
      },
    );

    test('cash debt block triggers when WalletC exceeds WalletA', () async {
      final db = await HailODatabase().open(databasePath: inMemoryDatabasePath);
      addTearDown(db.close);

      final walletService = WalletService(db);
      await walletService.upsertUser(userId: 'driver_2', role: 'driver');

      final result = await walletService.settleRideFinance(
        rideId: 'ride_cash_debt_1',
        driverId: 'driver_2',
        baseFareMinor: 1000,
        premiumSeatMarkupMinor: 0,
        cashCollectedMinor: 2000,
        idempotencyKey: 'settle_cash_debt_1',
      );

      expect(result['driver_blocked'], true);

      final blocked = await walletService.isDriverBlockedByCashDebt('driver_2');
      expect(blocked, true);
    });

    test('autosave split correctness and idempotency replay', () async {
      final db = await HailODatabase().open(databasePath: inMemoryDatabasePath);
      addTearDown(db.close);

      final walletService = WalletService(db);
      final moneyBoxService = MoneyBoxService(db);
      final autosaveService = AutosaveService(
        db,
        moneyBoxService: moneyBoxService,
      );

      await walletService.upsertUser(userId: 'owner_1', role: 'driver');
      await moneyBoxService.ensureAccount(
        ownerId: 'owner_1',
        tier: 2,
        autosavePercent: 20,
      );

      final first = await autosaveService.applyOnConfirmedCommissionCredit(
        ownerId: 'owner_1',
        destinationWalletType: WalletType.driverA,
        grossAmountMinor: 10000,
        sourceKind: AutosaveService.confirmedCommissionCredit,
        referenceId: 'commission_credit_1',
        idempotencyKey: 'autosave_split_1',
      );

      expect(first['saved_minor'], 2000);
      expect(first['remainder_minor'], 8000);
      expect(first['moneybox_principal_after_minor'], 2000);
      expect(first['moneybox_projected_bonus_after_minor'], 60);
      expect(first['moneybox_expected_after_minor'], 2060);
      expect(first['wallet_balance_after_minor'], 8000);

      final second = await autosaveService.applyOnConfirmedCommissionCredit(
        ownerId: 'owner_1',
        destinationWalletType: WalletType.driverA,
        grossAmountMinor: 10000,
        sourceKind: AutosaveService.confirmedCommissionCredit,
        referenceId: 'commission_credit_1',
        idempotencyKey: 'autosave_split_1',
      );
      expect(second['replayed'], true);

      final walletBalance = await walletService.getWalletBalanceMinor(
        ownerId: 'owner_1',
        walletType: WalletType.driverA,
      );
      expect(walletBalance, 8000);

      final walletLedgerRows = await db.query(
        'wallet_ledger',
        where: 'reference_id = ? AND kind = ?',
        whereArgs: const <Object>[
          'commission_credit_1',
          'confirmed_commission_credit',
        ],
      );
      final moneyboxLedgerRows = await db.query(
        'moneybox_ledger',
        where: 'reference_id = ? AND source_kind = ?',
        whereArgs: const <Object>[
          'commission_credit_1',
          'confirmed_commission_credit',
        ],
      );

      expect(walletLedgerRows.length, 1);
      expect(walletLedgerRows.first['idempotency_scope'], isNotNull);
      expect(walletLedgerRows.first['idempotency_key'], isNotNull);
      expect(moneyboxLedgerRows.length, 1);
      expect(moneyboxLedgerRows.first['idempotency_scope'], isNotNull);
      expect(moneyboxLedgerRows.first['idempotency_key'], isNotNull);

      final accountRows = await db.query(
        'moneybox_accounts',
        columns: const <String>[
          'principal_minor',
          'projected_bonus_minor',
          'expected_at_maturity_minor',
        ],
        where: 'owner_id = ?',
        whereArgs: const <Object>['owner_1'],
        limit: 1,
      );
      expect(accountRows.length, 1);
      expect(accountRows.first['principal_minor'], 2000);
      expect(accountRows.first['projected_bonus_minor'], 60);
      expect(accountRows.first['expected_at_maturity_minor'], 2060);
    });
  });
}
