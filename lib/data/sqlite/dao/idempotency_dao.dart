import 'package:hail_o_finance_core/sqlite_api.dart';

import '../../../domain/models/idempotency_record.dart';
import '../table_names.dart';

class IdempotencyClaimResult {
  const IdempotencyClaimResult({
    required this.record,
    required this.isNewClaim,
  });

  final IdempotencyRecord record;
  final bool isNewClaim;
}

abstract class IdempotencyStore {
  Future<IdempotencyClaimResult> claim({
    required String scope,
    required String key,
    String? requestHash,
  });

  Future<IdempotencyRecord> finalizeSuccess({
    required String scope,
    required String key,
    required String resultHash,
  });

  Future<IdempotencyRecord> finalizeFailure({
    required String scope,
    required String key,
    required String errorCode,
  });

  Future<IdempotencyRecord?> get({required String scope, required String key});
}

class IdempotencyDao implements IdempotencyStore {
  const IdempotencyDao(this.db);

  final DatabaseExecutor db;

  @override
  Future<IdempotencyClaimResult> claim({
    required String scope,
    required String key,
    String? requestHash,
  }) async {
    final now = DateTime.now().toUtc().toIso8601String();
    try {
      await db.insert(TableNames.idempotencyKeys, <String, Object?>{
        'scope': scope,
        'key': key,
        'request_hash': requestHash,
        'status': IdempotencyStatus.claimed.dbValue,
        'result_hash': null,
        'error_code': null,
        'created_at': now,
        'updated_at': now,
      }, conflictAlgorithm: ConflictAlgorithm.abort);
      final record = (await get(scope: scope, key: key))!;
      return IdempotencyClaimResult(record: record, isNewClaim: true);
    } on DatabaseException catch (_) {
      final existing = await get(scope: scope, key: key);
      if (existing == null) {
        rethrow;
      }
      return IdempotencyClaimResult(record: existing, isNewClaim: false);
    }
  }

  @override
  Future<IdempotencyRecord> finalizeSuccess({
    required String scope,
    required String key,
    required String resultHash,
  }) async {
    final now = DateTime.now().toUtc().toIso8601String();
    await db.update(
      TableNames.idempotencyKeys,
      <String, Object?>{
        'status': IdempotencyStatus.success.dbValue,
        'result_hash': resultHash,
        'error_code': null,
        'updated_at': now,
      },
      where: 'scope = ? AND key = ?',
      whereArgs: <Object>[scope, key],
      conflictAlgorithm: ConflictAlgorithm.abort,
    );
    return (await get(scope: scope, key: key))!;
  }

  @override
  Future<IdempotencyRecord> finalizeFailure({
    required String scope,
    required String key,
    required String errorCode,
  }) async {
    final now = DateTime.now().toUtc().toIso8601String();
    await db.update(
      TableNames.idempotencyKeys,
      <String, Object?>{
        'status': IdempotencyStatus.failed.dbValue,
        'error_code': errorCode,
        'updated_at': now,
      },
      where: 'scope = ? AND key = ?',
      whereArgs: <Object>[scope, key],
      conflictAlgorithm: ConflictAlgorithm.abort,
    );
    return (await get(scope: scope, key: key))!;
  }

  @override
  Future<IdempotencyRecord?> get({
    required String scope,
    required String key,
  }) async {
    final rows = await db.query(
      TableNames.idempotencyKeys,
      where: 'scope = ? AND key = ?',
      whereArgs: <Object>[scope, key],
      limit: 1,
    );
    if (rows.isEmpty) {
      return null;
    }
    return IdempotencyRecord.fromMap(rows.first);
  }
}
