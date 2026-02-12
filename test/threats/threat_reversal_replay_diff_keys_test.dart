import 'package:flutter_test/flutter_test.dart';
import 'package:hail_o_finance_core/data/sqlite/hailo_database.dart';
import 'package:hail_o_finance_core/domain/services/ledger_invariant_service.dart';
import 'package:hail_o_finance_core/domain/services/wallet_reversal_service.dart';
import 'package:sqflite/sqflite.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  test(
    'reversing same original ledger with different keys cannot duplicate reversal',
    () async {
      final now = DateTime.utc(2026, 2, 12, 13, 0);
      final db = await HailODatabase().open(databasePath: inMemoryDatabasePath);
      addTearDown(db.close);

      final originalLedgerId = await _seedLedgerForReversal(db, now: now);
      final service = WalletReversalService(db, nowUtc: () => now);

      final first = await service.reverseWalletLedgerEntry(
        originalLedgerId: originalLedgerId,
        requestedByUserId: 'admin_reverse_threat',
        requesterIsAdmin: true,
        reason: 'threat_test_reverse',
        idempotencyKey: 'reversal_key_1',
      );
      final second = await service.reverseWalletLedgerEntry(
        originalLedgerId: originalLedgerId,
        requestedByUserId: 'admin_reverse_threat',
        requesterIsAdmin: true,
        reason: 'threat_test_reverse',
        idempotencyKey: 'reversal_key_2',
      );

      expect(first['ok'], true);
      expect(second['ok'], true);
      expect(second['replayed'], true);

      final reversalCount = Sqflite.firstIntValue(
        await db.rawQuery(
          'SELECT COUNT(*) FROM wallet_reversals WHERE original_ledger_id = ?',
          <Object>[originalLedgerId],
        ),
      )!;
      expect(reversalCount, 1);

      final reversalLedgerCount = Sqflite.firstIntValue(
        await db.rawQuery(
          "SELECT COUNT(*) FROM wallet_ledger WHERE kind LIKE 'reversal:%'",
        ),
      )!;
      expect(reversalLedgerCount, 1);

      final invariants = await LedgerInvariantService(db).verifySnapshot();
      expect(invariants['ok'], true, reason: invariants.toString());
    },
  );
}

Future<int> _seedLedgerForReversal(Database db, {required DateTime now}) async {
  final nowIso = now.toIso8601String();
  await db.insert('users', <String, Object?>{
    'id': 'admin_reverse_threat',
    'role': 'admin',
    'created_at': nowIso,
    'updated_at': nowIso,
  }, conflictAlgorithm: ConflictAlgorithm.ignore);
  await db.insert('users', <String, Object?>{
    'id': 'driver_reverse_threat',
    'role': 'driver',
    'created_at': nowIso,
    'updated_at': nowIso,
  }, conflictAlgorithm: ConflictAlgorithm.ignore);
  await db.insert('wallets', <String, Object?>{
    'owner_id': 'driver_reverse_threat',
    'wallet_type': 'driver_a',
    'balance_minor': 5000,
    'reserved_minor': 0,
    'currency': 'NGN',
    'updated_at': nowIso,
    'created_at': nowIso,
  }, conflictAlgorithm: ConflictAlgorithm.replace);
  return db.insert('wallet_ledger', <String, Object?>{
    'owner_id': 'driver_reverse_threat',
    'wallet_type': 'driver_a',
    'direction': 'credit',
    'amount_minor': 5000,
    'balance_after_minor': 5000,
    'kind': 'seed_credit',
    'reference_id': 'seed_reverse',
    'idempotency_scope': 'seed_reverse',
    'idempotency_key': 'seed_reverse_1',
    'created_at': nowIso,
  }, conflictAlgorithm: ConflictAlgorithm.abort);
}
