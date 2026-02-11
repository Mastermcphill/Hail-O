import 'package:flutter_test/flutter_test.dart';
import 'package:hail_o_finance_core/data/sqlite/dao/route_polylines_dao.dart';
import 'package:hail_o_finance_core/data/sqlite/hailo_database.dart';
import 'package:hail_o_finance_core/domain/models/latlng.dart';
import 'package:hail_o_finance_core/domain/models/route_polyline_cache.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  test('route polyline cache DAO CRUD', () async {
    final db = await HailODatabase().open(databasePath: inMemoryDatabasePath);
    addTearDown(db.close);
    final dao = RoutePolylinesDao(db);
    final now = DateTime.utc(2026, 2, 11);

    final cache = RoutePolylineCache(
      routeId: 'route_cache_1',
      polyline: const <LatLng>[
        LatLng(latitude: 6.5244, longitude: 3.3792),
        LatLng(latitude: 6.6000, longitude: 3.5000),
      ],
      totalDistanceM: 23000,
      createdAt: now,
    );

    await dao.upsert(cache);
    final loaded = await dao.findByRouteId('route_cache_1');
    expect(loaded, isNotNull);
    expect(loaded!.polyline.length, 2);
    expect(loaded.totalDistanceM, 23000);

    await dao.deleteByRouteId('route_cache_1');
    expect(await dao.findByRouteId('route_cache_1'), isNull);
  });
}
