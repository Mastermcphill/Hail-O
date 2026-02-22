import 'package:flutter_test/flutter_test.dart';
import 'package:hail_o_finance_core/data/sqlite/dao/moneybox_ledger_dao.dart';
import 'package:hail_o_finance_core/data/sqlite/dao/wallet_ledger_dao.dart';
import 'package:hail_o_finance_core/data/sqlite/hailo_database.dart';
import 'package:hail_o_finance_core/domain/models/moneybox_ledger_entry.dart';
import 'package:hail_o_finance_core/domain/models/wallet.dart';
import 'package:hail_o_finance_core/domain/models/wallet_ledger_entry.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  test('wallet and moneybox ledgers are append-only', () async {
    final db = await HailODatabase().open(databasePath: inMemoryDatabasePath);
    addTearDown(db.close);

    final walletLedgerDao = WalletLedgerDao(db);
    final moneyBoxLedgerDao = MoneyBoxLedgerDao(db);
    final now = DateTime.utc(2026, 1, 1, 0, 0);

    final walletLedgerId = await walletLedgerDao.append(
      WalletLedgerEntry(
        ownerId: 'driver_append_only',
        walletType: WalletType.driverA,
        direction: LedgerDirection.credit,
        amountMinor: 5000,
        balanceAfterMinor: 5000,
        kind: 'commission_credit',
        referenceId: 'ref_wallet_1',
        idempotencyScope: 'wallet.credit',
        idempotencyKey: 'wallet_append_only_1',
        createdAt: now,
      ),
      viaOrchestrator: true,
    );

    final moneyboxLedgerId = await moneyBoxLedgerDao.append(
      MoneyBoxLedgerEntry(
        ownerId: 'driver_append_only',
        entryType: 'autosave_in',
        amountMinor: 2000,
        principalAfterMinor: 2000,
        projectedBonusAfterMinor: 60,
        expectedAfterMinor: 2060,
        sourceKind: 'confirmed_commission_credit',
        referenceId: 'ref_moneybox_1',
        idempotencyScope: 'moneybox.autosave',
        idempotencyKey: 'moneybox_append_only_1',
        createdAt: now,
      ),
    );

    expect(
      () async => db.update(
        'wallet_ledger',
        <String, Object?>{'amount_minor': 1},
        where: 'id = ?',
        whereArgs: <Object>[walletLedgerId],
      ),
      throwsA(isA<DatabaseException>()),
    );
    expect(
      () async => db.delete(
        'wallet_ledger',
        where: 'id = ?',
        whereArgs: <Object>[walletLedgerId],
      ),
      throwsA(isA<DatabaseException>()),
    );

    expect(
      () async => db.update(
        'moneybox_ledger',
        <String, Object?>{'amount_minor': 1},
        where: 'id = ?',
        whereArgs: <Object>[moneyboxLedgerId],
      ),
      throwsA(isA<DatabaseException>()),
    );
    expect(
      () async => db.delete(
        'moneybox_ledger',
        where: 'id = ?',
        whereArgs: <Object>[moneyboxLedgerId],
      ),
      throwsA(isA<DatabaseException>()),
    );
  });
}
