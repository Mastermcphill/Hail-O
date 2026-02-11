import 'package:sqflite/sqflite.dart';

import '../../../domain/models/ride_event.dart';
import '../table_names.dart';

class RideEventsDao {
  const RideEventsDao(this.db);

  final DatabaseExecutor db;

  Future<void> insert(RideEvent event) async {
    await db.insert(
      TableNames.rideEvents,
      event.toMap(),
      conflictAlgorithm: ConflictAlgorithm.abort,
    );
  }

  Future<RideEvent?> findByIdempotency({
    required String idempotencyScope,
    required String idempotencyKey,
  }) async {
    final rows = await db.query(
      TableNames.rideEvents,
      where: 'idempotency_scope = ? AND idempotency_key = ?',
      whereArgs: <Object>[idempotencyScope, idempotencyKey],
      limit: 1,
    );
    if (rows.isEmpty) {
      return null;
    }
    return RideEvent.fromMap(rows.first);
  }

  Future<List<RideEvent>> listByRideId(String rideId) async {
    final rows = await db.query(
      TableNames.rideEvents,
      where: 'ride_id = ?',
      whereArgs: <Object>[rideId],
      orderBy: 'created_at ASC',
    );
    return rows.map(RideEvent.fromMap).toList(growable: false);
  }
}
