import 'package:sqflite/sqflite.dart';

import '../../../domain/models/operation_journal_entry.dart';
import '../table_names.dart';

class OperationJournalDao {
  const OperationJournalDao(this.db);

  final DatabaseExecutor db;

  Future<void> insert(OperationJournalEntry entry) async {
    await db.insert(
      TableNames.operationJournal,
      entry.toMap(),
      conflictAlgorithm: ConflictAlgorithm.abort,
    );
  }

  Future<void> updateStatus({
    required String idempotencyScope,
    required String idempotencyKey,
    required OperationJournalStatus status,
    required DateTime updatedAt,
    String? lastError,
  }) async {
    await db.update(
      TableNames.operationJournal,
      <String, Object?>{
        'status': status.dbValue,
        'updated_at': updatedAt.toUtc().toIso8601String(),
        'last_error': lastError,
      },
      where: 'idempotency_scope = ? AND idempotency_key = ?',
      whereArgs: <Object>[idempotencyScope, idempotencyKey],
      conflictAlgorithm: ConflictAlgorithm.abort,
    );
  }

  Future<OperationJournalEntry?> findByScopeKey({
    required String idempotencyScope,
    required String idempotencyKey,
  }) async {
    final rows = await db.query(
      TableNames.operationJournal,
      where: 'idempotency_scope = ? AND idempotency_key = ?',
      whereArgs: <Object>[idempotencyScope, idempotencyKey],
      limit: 1,
    );
    if (rows.isEmpty) {
      return null;
    }
    return OperationJournalEntry.fromMap(rows.first);
  }

  Future<List<OperationJournalEntry>> listByStatuses(
    List<OperationJournalStatus> statuses,
  ) async {
    if (statuses.isEmpty) {
      return const <OperationJournalEntry>[];
    }
    final placeholders = List<String>.filled(statuses.length, '?').join(', ');
    final whereArgs = statuses
        .map((status) => status.dbValue)
        .toList(growable: false);
    final rows = await db.query(
      TableNames.operationJournal,
      where: 'status IN ($placeholders)',
      whereArgs: whereArgs,
      orderBy: 'updated_at ASC',
    );
    return rows.map(OperationJournalEntry.fromMap).toList(growable: false);
  }
}
