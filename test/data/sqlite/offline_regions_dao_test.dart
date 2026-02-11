import 'package:flutter_test/flutter_test.dart';
import 'package:hail_o_finance_core/data/sqlite/dao/offline_download_events_dao.dart';
import 'package:hail_o_finance_core/data/sqlite/dao/offline_regions_dao.dart';
import 'package:hail_o_finance_core/data/sqlite/hailo_database.dart';
import 'package:hail_o_finance_core/domain/models/offline_download_event.dart';
import 'package:hail_o_finance_core/domain/models/offline_region_record.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  test('offline region DAO CRUD + events', () async {
    final db = await HailODatabase().open(databasePath: inMemoryDatabasePath);
    addTearDown(db.close);
    final regionsDao = OfflineRegionsDao(db);
    final eventsDao = OfflineDownloadEventsDao(db);
    final now = DateTime.utc(2026, 2, 10);

    final record = OfflineRegionRecord(
      regionId: 'lagos_region',
      name: 'Lagos Metro',
      styleUri: 'mapbox://styles/mapbox/standard',
      minZoom: 8,
      maxZoom: 16,
      geometryJson: '{"test":true}',
      downloadedBytes: 0,
      completedResources: 0,
      status: 'downloading',
      createdAt: now,
    );

    await regionsDao.upsert(record);
    await regionsDao.updateProgress(
      regionId: record.regionId,
      downloadedBytes: 12345,
      completedResources: 50,
      status: 'completed',
    );
    await eventsDao.insert(
      OfflineDownloadEvent(
        regionId: record.regionId,
        ts: now,
        progress: 1,
        message: 'done',
      ),
    );

    final loaded = await regionsDao.findById(record.regionId);
    expect(loaded, isNotNull);
    expect(loaded!.status, 'completed');
    expect(loaded.downloadedBytes, 12345);

    final events = await eventsDao.listByRegion(record.regionId);
    expect(events.length, 1);
    expect(events.first.message, 'done');

    await regionsDao.deleteById(record.regionId);
    expect(await regionsDao.findById(record.regionId), isNull);
  });
}
