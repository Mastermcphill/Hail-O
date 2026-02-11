import 'package:flutter_test/flutter_test.dart';
import 'package:hail_o_finance_core/data/sqlite/hailo_database.dart';
import 'package:hail_o_finance_core/services/autosave_service.dart';
import 'package:hail_o_finance_core/services/finance_database.dart';
import 'package:hail_o_finance_core/services/moneybox_service.dart';
import 'package:hail_o_finance_core/services/wallet_service.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  test(
    'legacy finance services operate on canonical HailODatabase schema',
    () async {
      final db = await HailODatabase().open(databasePath: inMemoryDatabasePath);
      addTearDown(db.close);

      final walletService = WalletService(db);
      final moneyBoxService = MoneyBoxService(db);
      final autosaveService = AutosaveService(
        db,
        moneyBoxService: moneyBoxService,
      );

      await walletService.upsertUser(userId: 'driver_unified', role: 'driver');
      await moneyBoxService.ensureAccount(
        ownerId: 'driver_unified',
        tier: 2,
        autosavePercent: 25,
      );

      final split = await autosaveService.applyOnConfirmedCommissionCredit(
        ownerId: 'driver_unified',
        destinationWalletType: WalletType.driverA,
        grossAmountMinor: 10000,
        sourceKind: AutosaveService.confirmedCommissionCredit,
        referenceId: 'unified_commission_1',
        idempotencyKey: 'unified_split_1',
      );
      expect(split['saved_minor'], 2500);
      expect(split['remainder_minor'], 7500);

      final account = await db.query(
        'moneybox_accounts',
        columns: const <String>[
          'principal_minor',
          'projected_bonus_minor',
          'expected_at_maturity_minor',
        ],
        where: 'owner_id = ?',
        whereArgs: const <Object>['driver_unified'],
        limit: 1,
      );
      expect(account.length, 1);
      expect(account.first['principal_minor'], 2500);
      expect(account.first['projected_bonus_minor'], 75);
      expect(account.first['expected_at_maturity_minor'], 2575);

      final walletLedger = await db.query(
        'wallet_ledger',
        where: 'reference_id = ?',
        whereArgs: const <Object>['unified_commission_1'],
      );
      final moneyboxLedger = await db.query(
        'moneybox_ledger',
        where: 'reference_id = ?',
        whereArgs: const <Object>['unified_commission_1'],
      );
      expect(walletLedger.length, 1);
      expect(walletLedger.first['idempotency_scope'], 'autosave_split_credit');
      expect(walletLedger.first['idempotency_key'], 'unified_split_1:wallet');
      expect(moneyboxLedger.length, 1);
      expect(
        moneyboxLedger.first['idempotency_scope'],
        'autosave_split_credit',
      );
      expect(
        moneyboxLedger.first['idempotency_key'],
        'unified_split_1:moneybox',
      );

      final idemRows = await db.query(
        'idempotency_keys',
        columns: const <String>['status', 'result_hash', 'updated_at'],
        where: 'scope = ? AND "key" = ?',
        whereArgs: const <Object>['autosave_split_credit', 'unified_split_1'],
        limit: 1,
      );
      expect(idemRows.length, 1);
      expect(idemRows.first['status'], 'success');
      expect(idemRows.first['result_hash'], isNotNull);
      expect(idemRows.first['updated_at'], isNotNull);

      await expectLater(
        () async => db.query(
          'moneybox_accounts',
          columns: const <String>['principal'],
          limit: 1,
        ),
        throwsException,
      );
    },
  );
}
