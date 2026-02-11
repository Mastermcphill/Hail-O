import 'package:sqflite/sqflite.dart';

import '../../../domain/models/reconciliation_anomaly.dart';
import '../table_names.dart';

class ReconciliationDao {
  const ReconciliationDao(this.db);

  final Database db;

  Future<void> insertRun({
    required String runId,
    required String startedAt,
    required String status,
    String? finishedAt,
    String? notes,
  }) async {
    await db.insert(TableNames.reconciliationRuns, <String, Object?>{
      'id': runId,
      'started_at': startedAt,
      'finished_at': finishedAt,
      'status': status,
      'notes': notes,
    }, conflictAlgorithm: ConflictAlgorithm.replace);
  }

  Future<void> upsertAnomaly(ReconciliationAnomaly anomaly) async {
    await db.insert(
      TableNames.reconciliationAnomalies,
      anomaly.toMap(),
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  Future<List<ReconciliationAnomaly>> listAnomaliesByRun(String runId) async {
    final rows = await db.query(
      TableNames.reconciliationAnomalies,
      where: 'run_id = ?',
      whereArgs: <Object>[runId],
      orderBy: 'created_at DESC',
    );
    return rows.map(ReconciliationAnomaly.fromMap).toList(growable: false);
  }
}
