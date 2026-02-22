import 'package:flutter_test/flutter_test.dart';
import 'package:hail_o_finance_core/data/sqlite/dao/idempotency_dao.dart';
import 'package:hail_o_finance_core/data/sqlite/hailo_database.dart';
import 'package:hail_o_finance_core/domain/models/idempotency_record.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  test('claim and replay with success/failure finalize', () async {
    final db = await HailODatabase().open(databasePath: inMemoryDatabasePath);
    addTearDown(db.close);

    final store = IdempotencyDao(db);
    const scope = 'wallet.credit';
    const key = 'idem_123';

    final first = await store.claim(
      scope: scope,
      key: key,
      requestHash: 'request_hash_v1',
    );
    expect(first.isNewClaim, true);
    expect(first.record.status, IdempotencyStatus.claimed);

    final second = await store.claim(
      scope: scope,
      key: key,
      requestHash: 'request_hash_v1',
    );
    expect(second.isNewClaim, false);
    expect(second.record.status, IdempotencyStatus.claimed);

    final success = await store.finalizeSuccess(
      scope: scope,
      key: key,
      resultHash: 'result_hash_v1',
    );
    expect(success.status, IdempotencyStatus.success);
    expect(success.resultHash, 'result_hash_v1');

    final failed = await store.finalizeFailure(
      scope: scope,
      key: key,
      errorCode: 'already_settled',
    );
    expect(failed.status, IdempotencyStatus.failed);
    expect(failed.errorCode, 'already_settled');
  });
}
