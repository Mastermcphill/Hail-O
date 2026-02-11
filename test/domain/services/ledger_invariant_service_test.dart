import 'package:flutter_test/flutter_test.dart';
import 'package:hail_o_finance_core/data/sqlite/hailo_database.dart';
import 'package:hail_o_finance_core/domain/services/ledger_invariant_service.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  test('ledger invariant detects wallet vs ledger mismatch', () async {
    final now = DateTime.utc(2026, 2, 11, 12);
    final db = await HailODatabase().open(databasePath: inMemoryDatabasePath);
    addTearDown(db.close);

    await db.insert('wallets', <String, Object?>{
      'owner_id': 'owner_invariant_1',
      'wallet_type': 'driver_a',
      'balance_minor': 5000,
      'reserved_minor': 0,
      'currency': 'NGN',
      'updated_at': now.toIso8601String(),
      'created_at': now.toIso8601String(),
    });
    await db.insert('wallet_ledger', <String, Object?>{
      'owner_id': 'owner_invariant_1',
      'wallet_type': 'driver_a',
      'direction': 'credit',
      'amount_minor': 5000,
      'balance_after_minor': 5000,
      'kind': 'seed',
      'reference_id': 'seed_1',
      'idempotency_scope': 'seed_scope',
      'idempotency_key': 'seed_key',
      'created_at': now.toIso8601String(),
    });

    final invariant = LedgerInvariantService(db);
    final okSnapshot = await invariant.verifySnapshot();
    expect(okSnapshot['ok'], true);
    expect(okSnapshot['anomaly_count'], 0);

    await db.update(
      'wallets',
      <String, Object?>{
        'balance_minor': 1000,
        'updated_at': now.add(const Duration(minutes: 1)).toIso8601String(),
      },
      where: 'owner_id = ? AND wallet_type = ?',
      whereArgs: const <Object>['owner_invariant_1', 'driver_a'],
    );

    final badSnapshot = await invariant.verifySnapshot();
    expect(badSnapshot['ok'], false);
    expect((badSnapshot['anomalies'] as List<Object?>).isNotEmpty, true);
  });
}
