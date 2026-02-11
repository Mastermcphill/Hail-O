import 'package:sqflite/sqflite.dart';

import '../../../domain/errors/domain_errors.dart';
import '../../../domain/models/dispute_event.dart';
import '../table_names.dart';

class DisputeEventsDao {
  const DisputeEventsDao(this.db);

  final DatabaseExecutor db;

  Future<void> insert(
    DisputeEventRecord event, {
    required bool viaOrchestrator,
  }) async {
    if (!viaOrchestrator) {
      throw const DomainInvariantError(
        code: 'dispute_event_insert_requires_orchestrator',
      );
    }
    await db.insert(
      TableNames.disputeEvents,
      event.toMap(),
      conflictAlgorithm: ConflictAlgorithm.abort,
    );
  }

  Future<DisputeEventRecord?> findByIdempotency({
    required String idempotencyScope,
    required String idempotencyKey,
  }) async {
    final rows = await db.query(
      TableNames.disputeEvents,
      where: 'idempotency_scope = ? AND idempotency_key = ?',
      whereArgs: <Object>[idempotencyScope, idempotencyKey],
      limit: 1,
    );
    if (rows.isEmpty) {
      return null;
    }
    return DisputeEventRecord.fromMap(rows.first);
  }

  Future<List<DisputeEventRecord>> listByDisputeId(String disputeId) async {
    final rows = await db.query(
      TableNames.disputeEvents,
      where: 'dispute_id = ?',
      whereArgs: <Object>[disputeId],
      orderBy: 'created_at ASC',
    );
    return rows.map(DisputeEventRecord.fromMap).toList(growable: false);
  }

  Future<int> sumRefundMinorByDisputeId(String disputeId) async {
    final rows = await db.query(
      TableNames.disputeEvents,
      columns: <String>['payload_json'],
      where: 'dispute_id = ? AND event_type = ?',
      whereArgs: <Object>[disputeId, 'refund_applied'],
    );
    var total = 0;
    for (final row in rows) {
      final event = DisputeEventRecord.fromMap(row);
      final payload = event.payloadAsMap();
      total += (payload['refund_minor'] as num?)?.toInt() ?? 0;
    }
    return total;
  }
}
