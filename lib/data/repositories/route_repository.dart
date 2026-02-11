import '../../domain/models/route_chain.dart';
import '../../domain/models/route_node.dart';

abstract class RouteRepository {
  Future<void> upsertRoute(RouteChain route);
  Future<void> addRouteNode(RouteNode node);
  Future<RouteChain?> getRoute(String routeId);
  Future<List<RouteNode>> listRouteNodes(String routeId);
}
