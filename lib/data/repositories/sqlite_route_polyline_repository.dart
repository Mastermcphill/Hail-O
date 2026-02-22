import '../../domain/models/route_polyline_cache.dart';
import '../sqlite/dao/route_polylines_dao.dart';
import 'route_polyline_repository.dart';

class SqliteRoutePolylineRepository implements RoutePolylineRepository {
  const SqliteRoutePolylineRepository(this._dao);

  final RoutePolylinesDao _dao;

  @override
  Future<void> deleteByRouteId(String routeId) => _dao.deleteByRouteId(routeId);

  @override
  Future<RoutePolylineCache?> findByRouteId(String routeId) {
    return _dao.findByRouteId(routeId);
  }

  @override
  Future<List<RoutePolylineCache>> listAll() => _dao.listAll();

  @override
  Future<void> upsert(RoutePolylineCache cache) => _dao.upsert(cache);
}
