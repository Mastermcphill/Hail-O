import 'package:sqflite/sqflite.dart';

import '../../../domain/models/penalty_record.dart';
import '../table_names.dart';

class PenaltiesDao {
  const PenaltiesDao(this.db);

  final DatabaseExecutor db;

  Future<void> insert(PenaltyRecord record) async {
    await db.insert(
      TableNames.penalties,
      record.toMap(),
      conflictAlgorithm: ConflictAlgorithm.abort,
    );
  }

  Future<List<PenaltyRecord>> listByUserAndReason({
    required String userId,
    required String reason,
  }) async {
    final rows = await db.query(
      TableNames.penalties,
      where: 'user_id = ? AND reason = ?',
      whereArgs: <Object>[userId, reason],
      orderBy: 'created_at DESC',
    );
    return rows.map(PenaltyRecord.fromMap).toList(growable: false);
  }
}
