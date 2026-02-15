import 'package:hail_o_finance_core/sqlite_api.dart';

import '../../../domain/models/route_chain.dart';
import '../../../domain/models/route_node.dart';
import '../table_names.dart';

class RoutesDao {
  const RoutesDao(this.db);

  final Database db;

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
