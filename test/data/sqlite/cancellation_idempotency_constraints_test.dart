import 'package:flutter_test/flutter_test.dart';
import 'package:hail_o_finance_core/data/sqlite/hailo_database.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  test('wallet_ledger enforces unique idempotency scope/key', () async {
    final db = await HailODatabase().open(databasePath: inMemoryDatabasePath);
    addTearDown(db.close);
    final nowIso = DateTime.utc(2026, 3, 7, 12).toIso8601String();

    await db.insert('wallet_ledger', <String, Object?>{
      'owner_id': 'owner_idem_1',
      'wallet_type': 'driver_a',
      'direction': 'credit',
      'amount_minor': 1000,
      'balance_after_minor': 1000,
      'kind': 'cancellation_penalty_credit',
      'reference_id': 'ride_idem_1',
      'idempotency_scope': 'cancellation_penalty',
      'idempotency_key': 'dup_key_1',
      'created_at': nowIso,
    });

    expect(
      () => db.insert('wallet_ledger', <String, Object?>{
        'owner_id': 'owner_idem_2',
        'wallet_type': 'platform',
        'direction': 'credit',
        'amount_minor': 1000,
        'balance_after_minor': 1000,
        'kind': 'cancellation_penalty_credit',
        'reference_id': 'ride_idem_2',
        'idempotency_scope': 'cancellation_penalty',
        'idempotency_key': 'dup_key_1',
        'created_at': nowIso,
      }),
      throwsA(isA<DatabaseException>()),
    );
  });

  test('penalty_records enforces unique idempotency scope/key', () async {
    final db = await HailODatabase().open(databasePath: inMemoryDatabasePath);
    addTearDown(db.close);
    final nowIso = DateTime.utc(2026, 3, 7, 12).toIso8601String();

    await db.insert('users', <String, Object?>{
      'id': 'rider_penalty_1',
      'role': 'rider',
      'created_at': nowIso,
      'updated_at': nowIso,
    });
    await db.insert('rides', <String, Object?>{
      'id': 'ride_penalty_1',
      'rider_id': 'rider_penalty_1',
      'driver_id': null,
      'trip_scope': 'intra_city',
      'status': 'accepted',
      'bidding_mode': 1,
      'base_fare_minor': 0,
      'premium_markup_minor': 0,
      'charter_mode': 0,
      'daily_rate_minor': 0,
      'total_fare_minor': 0,
      'connection_fee_minor': 0,
      'connection_fee_paid': 0,
      'created_at': nowIso,
      'updated_at': nowIso,
    });

    await db.insert('penalty_records', <String, Object?>{
      'id': 'penalty_record_1',
      'ride_id': 'ride_penalty_1',
      'user_id': 'rider_penalty_1',
      'amount_minor': 0,
      'rule_code': 'connection_fee_timeout_auto_cancelled',
      'status': 'assessed',
      'created_at': nowIso,
      'idempotency_scope': 'cancellation_penalty',
      'idempotency_key': 'dup_key_2',
      'ride_type': 'intra_city',
      'total_fare_minor': 0,
      'collected_to_owner_id': null,
      'collected_to_wallet_type': null,
    });

    expect(
      () => db.insert('penalty_records', <String, Object?>{
        'id': 'penalty_record_2',
        'ride_id': 'ride_penalty_1',
        'user_id': 'rider_penalty_1',
        'amount_minor': 0,
        'rule_code': 'connection_fee_timeout_auto_cancelled',
        'status': 'assessed',
        'created_at': nowIso,
        'idempotency_scope': 'cancellation_penalty',
        'idempotency_key': 'dup_key_2',
        'ride_type': 'intra_city',
        'total_fare_minor': 0,
        'collected_to_owner_id': null,
        'collected_to_wallet_type': null,
      }),
      throwsA(isA<DatabaseException>()),
    );
  });
}
