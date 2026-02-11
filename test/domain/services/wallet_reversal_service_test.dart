import 'package:flutter_test/flutter_test.dart';
import 'package:hail_o_finance_core/data/sqlite/hailo_database.dart';
import 'package:hail_o_finance_core/domain/services/wallet_reversal_service.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  test('wallet reversal rejects non-admin requesters', () async {
    final db = await HailODatabase().open(databasePath: inMemoryDatabasePath);
    addTearDown(db.close);
    final service = WalletReversalService(db);

    expect(
      () => service.reverseWalletLedgerEntry(
        originalLedgerId: 1,
        requestedByUserId: 'user_1',
        requesterIsAdmin: false,
        reason: 'unauthorized',
        idempotencyKey: 'reverse_unauthorized_1',
      ),
      throwsStateError,
    );
  });

  test('wallet reversal is idempotent and linked to original ledger', () async {
    final now = DateTime.utc(2026, 3, 11, 10);
    final nowIso = now.toIso8601String();
    final db = await HailODatabase().open(databasePath: inMemoryDatabasePath);
    addTearDown(db.close);
    final service = WalletReversalService(db, nowUtc: () => now);

    await db.insert('users', <String, Object?>{
      'id': 'admin_reversal_1',
      'role': 'admin',
      'created_at': nowIso,
      'updated_at': nowIso,
    });
    await db.insert('users', <String, Object?>{
      'id': 'driver_reversal_1',
      'role': 'driver',
      'created_at': nowIso,
      'updated_at': nowIso,
    });
    await db.insert('wallets', <String, Object?>{
      'owner_id': 'driver_reversal_1',
      'wallet_type': 'driver_a',
      'balance_minor': 5000,
      'reserved_minor': 0,
      'currency': 'NGN',
      'updated_at': nowIso,
      'created_at': nowIso,
    });
    final originalLedgerId = await db.insert('wallet_ledger', <String, Object?>{
      'owner_id': 'driver_reversal_1',
      'wallet_type': 'driver_a',
      'direction': 'credit',
      'amount_minor': 3000,
      'balance_after_minor': 5000,
      'kind': 'test_credit',
      'reference_id': 'ride_reverse_1',
      'idempotency_scope': 'seed_scope',
      'idempotency_key': 'seed_key',
      'created_at': nowIso,
    });

    final first = await service.reverseWalletLedgerEntry(
      originalLedgerId: originalLedgerId,
      requestedByUserId: 'admin_reversal_1',
      requesterIsAdmin: true,
      reason: 'dispute_adjustment',
      idempotencyKey: 'reverse_once_1',
    );
    expect(first['ok'], true);
    expect(first['replayed'], false);

    final replaySameKey = await service.reverseWalletLedgerEntry(
      originalLedgerId: originalLedgerId,
      requestedByUserId: 'admin_reversal_1',
      requesterIsAdmin: true,
      reason: 'dispute_adjustment',
      idempotencyKey: 'reverse_once_1',
    );
    expect(replaySameKey['ok'], true);
    expect(replaySameKey['replayed'], true);

    final replayDifferentKey = await service.reverseWalletLedgerEntry(
      originalLedgerId: originalLedgerId,
      requestedByUserId: 'admin_reversal_1',
      requesterIsAdmin: true,
      reason: 'dispute_adjustment',
      idempotencyKey: 'reverse_once_2',
    );
    expect(replayDifferentKey['ok'], true);
    expect(replayDifferentKey['replayed'], true);

    final walletRows = await db.query(
      'wallets',
      columns: <String>['balance_minor'],
      where: 'owner_id = ? AND wallet_type = ?',
      whereArgs: const <Object>['driver_reversal_1', 'driver_a'],
      limit: 1,
    );
    expect(walletRows.first['balance_minor'], 2000);

    final reversalLedgerRows = await db.query(
      'wallet_ledger',
      where: 'idempotency_scope = ?',
      whereArgs: const <Object>['wallet_reversal'],
    );
    expect(reversalLedgerRows.length, 1);

    final reversalRows = await db.query('wallet_reversals');
    expect(reversalRows.length, 1);
    expect(reversalRows.first['original_ledger_id'], originalLedgerId);
  });
}
