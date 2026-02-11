import 'package:sqflite/sqflite.dart';

import '../../../domain/models/dispute.dart';
import '../table_names.dart';

class DisputesDao {
  const DisputesDao(this.db);

  final DatabaseExecutor db;

  Future<void> insert(DisputeRecord record) async {
    await db.insert(
      TableNames.disputes,
      record.toMap(),
      conflictAlgorithm: ConflictAlgorithm.abort,
    );
  }

  Future<void> update(DisputeRecord record) async {
    await db.update(
      TableNames.disputes,
      record.toMap(),
      where: 'id = ?',
      whereArgs: <Object>[record.id],
      conflictAlgorithm: ConflictAlgorithm.abort,
    );
  }

  Future<DisputeRecord?> findById(String disputeId) async {
    final rows = await db.query(
      TableNames.disputes,
      where: 'id = ?',
      whereArgs: <Object>[disputeId],
      limit: 1,
    );
    if (rows.isEmpty) {
      return null;
    }
    return DisputeRecord.fromMap(rows.first);
  }

  Future<List<DisputeRecord>> listByRideId(String rideId) async {
    final rows = await db.query(
      TableNames.disputes,
      where: 'ride_id = ?',
      whereArgs: <Object>[rideId],
      orderBy: 'created_at DESC',
    );
    return rows.map(DisputeRecord.fromMap).toList(growable: false);
  }
}
