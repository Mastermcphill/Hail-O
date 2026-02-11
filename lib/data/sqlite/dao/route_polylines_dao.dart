import 'package:sqflite/sqflite.dart';

import '../../../domain/models/route_polyline_cache.dart';
import '../table_names.dart';

class RoutePolylinesDao {
  const RoutePolylinesDao(this.db);

  final Database db;

  Future<void> upsert(RoutePolylineCache cache) async {
    await db.insert(
      TableNames.routePolylines,
      cache.toMap(),
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  Future<RoutePolylineCache?> findByRouteId(String routeId) async {
    final rows = await db.query(
      TableNames.routePolylines,
      where: 'route_id = ?',
      whereArgs: <Object>[routeId],
      limit: 1,
    );
    if (rows.isEmpty) {
      return null;
    }
    return RoutePolylineCache.fromMap(rows.first);
  }

  Future<void> deleteByRouteId(String routeId) async {
    await db.delete(
      TableNames.routePolylines,
      where: 'route_id = ?',
      whereArgs: <Object>[routeId],
    );
  }

  Future<List<RoutePolylineCache>> listAll() async {
    final rows = await db.query(
      TableNames.routePolylines,
      orderBy: 'created_at DESC',
    );
    return rows.map(RoutePolylineCache.fromMap).toList(growable: false);
  }
}
