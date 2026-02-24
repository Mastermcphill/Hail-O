import 'package:shelf/shelf.dart';
import 'package:shelf_router/shelf_router.dart';
import 'package:sqflite_common/sqlite_api.dart';
import 'package:uuid/uuid.dart';

import '../../../lib/data/sqlite/dao/routes_dao.dart';
import '../../../lib/domain/errors/domain_errors.dart';
import '../../../lib/domain/models/route_chain.dart';
import '../../../lib/domain/models/route_node.dart';
import '../../../lib/domain/services/route_matching_service.dart';
import '../../infra/request_context.dart';
import '../../server/http_utils.dart';

class RoutesController {
  RoutesController(
    this.db, {
    RouteMatchingService? routeMatchingService,
    Uuid? uuid,
    DateTime Function()? nowUtc,
  }) : _routeMatchingService = routeMatchingService ?? RouteMatchingService(),
       _uuid = uuid ?? const Uuid(),
       _nowUtc = nowUtc ?? (() => DateTime.now().toUtc());

  final Database db;
  final RouteMatchingService _routeMatchingService;
  final Uuid _uuid;
  final DateTime Function() _nowUtc;

  Router get router {
    final router = Router();
    router.post('/', _createRoute);
    router.get('/match', _matchRoutes);
    return router;
  }

  Future<Response> _createRoute(Request request) async {
    final role = (request.requestContext.role ?? '').trim().toLowerCase();
    if (role != 'driver' && role != 'admin') {
      throw const UnauthorizedActionError(code: 'forbidden');
    }

    final payload = await readJsonBody(request);
    final rawNodes = payload['nodes'];
    if (rawNodes is! List || rawNodes.length < 2) {
      throw const DomainInvariantError(code: 'route_nodes_minimum_two');
    }

    final now = _nowUtc();
    final routeId = (payload['id'] as String?)?.trim().isNotEmpty == true
        ? (payload['id'] as String).trim()
        : _uuid.v4();
    final contextDriverId = (request.requestContext.userId ?? '').trim();
    final adminDriverId = (payload['driver_id'] as String?)?.trim() ?? '';
    final driverId = role == 'admin' ? adminDriverId : contextDriverId;
    if (driverId.isEmpty) {
      throw const DomainInvariantError(code: 'driver_id_required');
    }

    final nodes = <RouteNode>[];
    for (var i = 0; i < rawNodes.length; i++) {
      final item = rawNodes[i];
      if (item is! Map) {
        continue;
      }
      final map = item.map(
        (key, value) => MapEntry<String, dynamic>(key.toString(), value),
      );
      final label = (map['name'] ?? map['label'] ?? '').toString().trim();
      if (label.isEmpty) {
        continue;
      }
      nodes.add(
        RouteNode(
          id: _uuid.v4(),
          routeId: routeId,
          sequenceNo: nodes.length,
          label: label,
          latitude: (map['latitude'] as num?)?.toDouble(),
          longitude: (map['longitude'] as num?)?.toDouble(),
          createdAt: now,
        ),
      );
    }
    if (nodes.length < 2) {
      throw const DomainInvariantError(code: 'route_nodes_minimum_two');
    }

    final route = RouteChain(
      id: routeId,
      driverId: driverId,
      origin: nodes.first.label,
      destination: nodes.last.label,
      polyline: (payload['polyline'] as String?)?.trim(),
      totalDistanceKm: (payload['total_distance_km'] as num?)?.toDouble() ?? 0,
      status: ((payload['is_online'] as bool?) ?? true) ? 'active' : 'draft',
      createdAt: now,
      updatedAt: now,
      nodes: nodes,
    );

    await db.transaction((txn) async {
      final dao = RoutesDao(txn);
      await dao.upsertRoute(route);
      for (final node in nodes) {
        await dao.insertNode(node);
      }
    });

    return jsonResponse(201, <String, Object?>{
      'ok': true,
      'route': <String, Object?>{
        ...route.toMap(),
        'nodes': nodes.map((node) => node.toMap()).toList(growable: false),
      },
    });
  }

  Future<Response> _matchRoutes(Request request) async {
    final from = (request.url.queryParameters['from'] ?? '').trim();
    final to = (request.url.queryParameters['to'] ?? '').trim();
    if (from.isEmpty || to.isEmpty) {
      throw const DomainInvariantError(code: 'route_match_from_to_required');
    }
    final dao = RoutesDao(db);
    final routes = await dao.listRoutesWithNodes();
    final matches = routes
        .where((route) {
          return _routeMatchingService.matchesSubRouteByLabels(
            routeNodes: route.nodes,
            pickupLabel: from,
            dropoffLabel: to,
          );
        })
        .toList(growable: false);

    return jsonResponse(200, <String, Object?>{
      'ok': true,
      'matches': matches
          .map((route) {
            return <String, Object?>{
              ...route.toMap(),
              'nodes': route.nodes
                  .map((node) => node.toMap())
                  .toList(growable: false),
            };
          })
          .toList(growable: false),
    });
  }
}
