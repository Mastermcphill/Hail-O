import 'package:sqflite/sqflite.dart';

import '../../../domain/models/vehicle.dart';
import '../table_names.dart';

class VehiclesDao {
  const VehiclesDao(this.db);

  final Database db;

  Future<void> upsert(Vehicle vehicle) async {
    await db.insert(
      TableNames.vehicles,
      vehicle.toMap(),
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  Future<Vehicle?> findById(String vehicleId) async {
    final rows = await db.query(
      TableNames.vehicles,
      where: 'id = ?',
      whereArgs: <Object>[vehicleId],
      limit: 1,
    );
    if (rows.isEmpty) {
      return null;
    }
    return Vehicle.fromMap(rows.first);
  }

  Future<List<Vehicle>> listByDriver(String driverId) async {
    final rows = await db.query(
      TableNames.vehicles,
      where: 'driver_id = ?',
      whereArgs: <Object>[driverId],
      orderBy: 'created_at DESC',
    );
    return rows.map(Vehicle.fromMap).toList(growable: false);
  }
}
