import 'package:sqflite/sqflite.dart';

import '../../../domain/models/penalty_audit_record.dart';
import '../table_names.dart';

class PenaltyRecordsDao {
  const PenaltyRecordsDao(this.db);

  final DatabaseExecutor db;

  Future<void> insert(PenaltyAuditRecord record) async {
    await db.insert(
      TableNames.penaltyRecords,
      record.toMap(),
      conflictAlgorithm: ConflictAlgorithm.abort,
    );
  }

  Future<PenaltyAuditRecord?> findByIdempotency({
    required String idempotencyScope,
    required String idempotencyKey,
  }) async {
    final rows = await db.query(
      TableNames.penaltyRecords,
      where: 'idempotency_scope = ? AND idempotency_key = ?',
      whereArgs: <Object>[idempotencyScope, idempotencyKey],
      limit: 1,
    );
    if (rows.isEmpty) {
      return null;
    }
    return PenaltyAuditRecord.fromMap(rows.first);
  }
}
