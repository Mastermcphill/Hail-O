import 'package:hail_o_finance_core/sqlite_api.dart';

import '../../../domain/models/seat.dart';
import '../table_names.dart';

class SeatsDao {
  const SeatsDao(this.db);

  final DatabaseExecutor db;

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

  Future<int> sumMarkupMinorByRide(String rideId) async {
    final seats = await listByRide(rideId);
    var total = 0;
    for (final seat in seats) {
      total += seat.markupMinor;
    }
    return total;
  }
}
