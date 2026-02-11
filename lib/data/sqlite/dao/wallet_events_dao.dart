import 'package:sqflite/sqflite.dart';

import '../../../domain/errors/domain_errors.dart';
import '../table_names.dart';

class WalletEventsDao {
  const WalletEventsDao(this.db);

  final DatabaseExecutor db;

  Future<void> insert({
    required String id,
    required String ownerId,
    required String walletType,
    required String eventType,
    required String payloadJson,
    required String idempotencyScope,
    required String idempotencyKey,
    required String createdAtIso,
    required bool viaOrchestrator,
  }) async {
    if (!viaOrchestrator) {
      throw const DomainInvariantError(
        code: 'wallet_event_insert_requires_orchestrator',
      );
    }
    await db.insert(TableNames.walletEvents, <String, Object?>{
      'id': id,
      'owner_id': ownerId,
      'wallet_type': walletType,
      'event_type': eventType,
      'payload_json': payloadJson,
      'idempotency_scope': idempotencyScope,
      'idempotency_key': idempotencyKey,
      'created_at': createdAtIso,
    }, conflictAlgorithm: ConflictAlgorithm.abort);
  }

  Future<Map<String, Object?>?> findByIdempotency({
    required String idempotencyScope,
    required String idempotencyKey,
  }) async {
    final rows = await db.query(
      TableNames.walletEvents,
      where: 'idempotency_scope = ? AND idempotency_key = ?',
      whereArgs: <Object>[idempotencyScope, idempotencyKey],
      limit: 1,
    );
    if (rows.isEmpty) {
      return null;
    }
    return Map<String, Object?>.from(rows.first);
  }
}
