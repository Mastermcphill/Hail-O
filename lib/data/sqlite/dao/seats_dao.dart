import 'package:sqflite/sqflite.dart';

import '../../../domain/models/seat.dart';
import '../table_names.dart';

class SeatsDao {
  const SeatsDao(this.db);

  final Database db;

  Future<void> upsert(Seat seat) async {
    await db.insert(
      TableNames.seats,
      seat.toMap(),
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  Future<List<Seat>> listByRide(String rideId) async {
    final rows = await db.query(
      TableNames.seats,
      where: 'ride_id = ?',
      whereArgs: <Object>[rideId],
      orderBy: 'created_at ASC',
    );
    return rows.map(Seat.fromMap).toList(growable: false);
  }
}
