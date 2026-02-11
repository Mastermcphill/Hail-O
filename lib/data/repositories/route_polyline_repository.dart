import '../../domain/models/route_polyline_cache.dart';

abstract class RoutePolylineRepository {
  Future<void> upsert(RoutePolylineCache cache);
  Future<RoutePolylineCache?> findByRouteId(String routeId);
  Future<void> deleteByRouteId(String routeId);
  Future<List<RoutePolylineCache>> listAll();
}
