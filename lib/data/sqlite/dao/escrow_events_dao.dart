import 'package:hail_o_finance_core/sqlite_api.dart';

import '../../../domain/errors/domain_errors.dart';
import '../table_names.dart';

class EscrowEventsDao {
  const EscrowEventsDao(this.db);

  final DatabaseExecutor db;

  Future<void> insert({
    required String id,
    required String escrowId,
    required String rideId,
    required String eventType,
    required String payloadJson,
    required String idempotencyScope,
    required String idempotencyKey,
    required String createdAtIso,
    String? actorId,
    required bool viaOrchestrator,
  }) async {
    if (!viaOrchestrator) {
      throw const DomainInvariantError(
        code: 'escrow_event_insert_requires_orchestrator',
      );
    }
    await db.insert(TableNames.escrowEvents, <String, Object?>{
      'id': id,
      'escrow_id': escrowId,
      'ride_id': rideId,
      'event_type': eventType,
      'actor_id': actorId,
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
      TableNames.escrowEvents,
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
