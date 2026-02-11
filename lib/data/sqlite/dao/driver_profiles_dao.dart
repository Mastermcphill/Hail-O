import 'package:sqflite/sqflite.dart';

import '../../../domain/models/driver_profile.dart';
import '../table_names.dart';

class DriverProfilesDao {
  const DriverProfilesDao(this.db);

  final DatabaseExecutor db;

  Future<void> upsert(DriverProfile profile) async {
    await db.insert(
      TableNames.driverProfiles,
      profile.toMap(),
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  Future<DriverProfile?> findByDriverId(String driverId) async {
    final rows = await db.query(
      TableNames.driverProfiles,
      where: 'driver_id = ?',
      whereArgs: <Object>[driverId],
      limit: 1,
    );
    if (rows.isEmpty) {
      return null;
    }
    return DriverProfile.fromMap(rows.first);
  }
}
