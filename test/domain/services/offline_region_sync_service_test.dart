import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:hail_o_finance_core/data/repositories/sqlite_offline_region_repository.dart';
import 'package:hail_o_finance_core/data/sqlite/dao/offline_download_events_dao.dart';
import 'package:hail_o_finance_core/data/sqlite/dao/offline_regions_dao.dart';
import 'package:hail_o_finance_core/data/sqlite/hailo_database.dart';
import 'package:hail_o_finance_core/domain/models/latlng.dart';
import 'package:hail_o_finance_core/domain/services/offline_region_sync_service.dart';
import 'package:hail_o_finance_core/integrations/mapbox/offline_mapbox_manager.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

class _FakeOfflineMapboxManager implements OfflineMapboxManager {
  final StreamController<OfflineDownloadProgressUpdate> controller =
      StreamController<OfflineDownloadProgressUpdate>.broadcast();
  bool shouldThrow = false;
  final Set<String> _regions = <String>{};

  @override
  Future<void> deleteRegion(String regionId) async {
    _regions.remove(regionId);
    controller.add(
      OfflineDownloadProgressUpdate(
        regionId: regionId,
        progress: 0,
        downloadedBytes: 0,
        completedResources: 0,
        status: 'deleted',
        message: 'deleted',
      ),
    );
  }

  @override
  Future<void> downloadStylePack({required String styleUri}) async {
    if (shouldThrow) {
      throw StateError('style_pack_failure');
    }
  }

  @override
  Future<void> downloadTileRegion({
    required String regionId,
    required OfflineRegionBounds bounds,
    required double minZoom,
    required double maxZoom,
    required String styleUri,
  }) async {
    if (shouldThrow) {
      throw StateError('tile_region_failure');
    }
    _regions.add(regionId);
    controller.add(
      OfflineDownloadProgressUpdate(
        regionId: regionId,
        progress: 0.5,
        downloadedBytes: 500,
        completedResources: 10,
        status: 'downloading',
        message: 'half',
      ),
    );
    controller.add(
      OfflineDownloadProgressUpdate(
        regionId: regionId,
        progress: 1,
        downloadedBytes: 1000,
        completedResources: 20,
        status: 'completed',
        message: 'done',
      ),
    );
  }

  @override
  Future<List<String>> listDownloadedRegions() async {
    return _regions.toList(growable: false);
  }

  @override
  Stream<OfflineDownloadProgressUpdate> observeDownloadProgress({
    String? regionId,
  }) {
    if (regionId == null) {
      return controller.stream;
    }
    return controller.stream.where((event) => event.regionId == regionId);
  }
}

void main() {
  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  test('progress stream emitted and persisted, errors persisted', () async {
    final db = await HailODatabase().open(databasePath: inMemoryDatabasePath);
    addTearDown(db.close);
    final repository = SqliteOfflineRegionRepository(
      regionsDao: OfflineRegionsDao(db),
      eventsDao: OfflineDownloadEventsDao(db),
    );
    final manager = _FakeOfflineMapboxManager();
    final service = OfflineRegionSyncService(
      mapboxManager: manager,
      repository: repository,
      nowUtc: () => DateTime.utc(2026, 2, 12),
    );
    addTearDown(service.dispose);

    service.observeAndPersistProgress(regionId: 'region_test');

    await service.downloadRegion(
      regionId: 'region_test',
      name: 'Test Region',
      bounds: const OfflineRegionBounds(
        southWest: LatLng(latitude: 6.5, longitude: 3.3),
        northEast: LatLng(latitude: 6.7, longitude: 3.5),
      ),
      styleUri: 'mapbox://styles/mapbox/standard',
      minZoom: 8,
      maxZoom: 16,
    );

    final region = await repository.getRegion('region_test');
    expect(region, isNotNull);
    expect(region!.status, anyOf('downloading', 'completed'));
    final events = await repository.listDownloadEvents('region_test');
    expect(events.isNotEmpty, true);

    manager.shouldThrow = true;
    await expectLater(
      service.downloadRegion(
        regionId: 'region_error',
        name: 'Error Region',
        bounds: const OfflineRegionBounds(
          southWest: LatLng(latitude: 6.1, longitude: 3.1),
          northEast: LatLng(latitude: 6.2, longitude: 3.2),
        ),
        styleUri: 'mapbox://styles/mapbox/standard',
        minZoom: 8,
        maxZoom: 16,
      ),
      throwsA(isA<StateError>()),
    );
    final failed = await repository.getRegion('region_error');
    expect(failed, isNotNull);
    expect(failed!.status, 'failed');
  });
}
