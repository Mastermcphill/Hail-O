import '../../domain/models/route_chain.dart';
import '../../domain/models/route_node.dart';
import '../sqlite/dao/routes_dao.dart';
import 'route_repository.dart';

class SqliteRouteRepository implements RouteRepository {
  const SqliteRouteRepository(this._dao);

  final RoutesDao _dao;

  @override
  Future<void> addRouteNode(RouteNode node) => _dao.insertNode(node);

  @override
  Future<RouteChain?> getRoute(String routeId) => _dao.findRouteById(routeId);

  @override
  Future<List<RouteNode>> listRouteNodes(String routeId) =>
      _dao.listNodes(routeId);

  @override
  Future<void> upsertRoute(RouteChain route) => _dao.upsertRoute(route);
}
