import 'package:hailo_shared/sqlite_api.dart';

import '../../../domain/models/route_chain.dart';
import '../../../domain/models/route_node.dart';
import '../table_names.dart';

class RoutesDao {
  const RoutesDao(this.db);

  final DatabaseExecutor db;

  Future<void> upsertRoute(RouteChain route) async {
    await db.insert(
      TableNames.routes,
      route.toMap(),
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  Future<void> insertNode(RouteNode node) async {
    await db.insert(
      TableNames.routeNodes,
      node.toMap(),
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  Future<RouteChain?> findRouteById(String routeId) async {
    final routes = await db.query(
      TableNames.routes,
      where: 'id = ?',
      whereArgs: <Object>[routeId],
      limit: 1,
    );
    if (routes.isEmpty) {
      return null;
    }
    final nodes = await listNodes(routeId);
    return RouteChain.fromMap(routes.first, nodes: nodes);
  }

  Future<List<RouteChain>> listRoutes() async {
    final rows = await db.query(TableNames.routes, orderBy: 'created_at DESC');
    return rows
        .map((row) => RouteChain.fromMap(Map<String, Object?>.from(row)))
        .toList(growable: false);
  }

  Future<List<RouteChain>> listRoutesWithNodes() async {
    final routes = await listRoutes();
    final resolved = <RouteChain>[];
    for (final route in routes) {
      final nodes = await listNodes(route.id);
      resolved.add(
        RouteChain(
          id: route.id,
          driverId: route.driverId,
          origin: route.origin,
          destination: route.destination,
          polyline: route.polyline,
          totalDistanceKm: route.totalDistanceKm,
          status: route.status,
          createdAt: route.createdAt,
          updatedAt: route.updatedAt,
          nodes: nodes,
        ),
      );
    }
    return resolved;
  }

  Future<List<RouteNode>> listNodes(String routeId) async {
    final rows = await db.query(
      TableNames.routeNodes,
      where: 'route_id = ?',
      whereArgs: <Object>[routeId],
      orderBy: 'sequence_no ASC',
    );
    return rows.map(RouteNode.fromMap).toList(growable: false);
  }
}
