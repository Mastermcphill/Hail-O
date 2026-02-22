import '../../domain/models/offline_download_event.dart';
import '../../domain/models/offline_region_record.dart';
import '../sqlite/dao/offline_download_events_dao.dart';
import '../sqlite/dao/offline_regions_dao.dart';
import 'offline_region_repository.dart';

class SqliteOfflineRegionRepository implements OfflineRegionRepository {
  const SqliteOfflineRegionRepository({
    required OfflineRegionsDao regionsDao,
    required OfflineDownloadEventsDao eventsDao,
  }) : _regionsDao = regionsDao,
       _eventsDao = eventsDao;

  final OfflineRegionsDao _regionsDao;
  final OfflineDownloadEventsDao _eventsDao;

  @override
  Future<int> appendDownloadEvent(OfflineDownloadEvent event) {
    return _eventsDao.insert(event);
  }

  @override
  Future<void> deleteRegion(String regionId) async {
    await _eventsDao.deleteByRegion(regionId);
    await _regionsDao.deleteById(regionId);
  }

  @override
  Future<OfflineRegionRecord?> getRegion(String regionId) {
    return _regionsDao.findById(regionId);
  }

  @override
  Future<List<OfflineDownloadEvent>> listDownloadEvents(String regionId) {
    return _eventsDao.listByRegion(regionId);
  }

  @override
  Future<List<OfflineRegionRecord>> listRegions() => _regionsDao.listAll();

  @override
  Future<void> updateRegionProgress({
    required String regionId,
    required int downloadedBytes,
    required int completedResources,
    required String status,
  }) {
    return _regionsDao.updateProgress(
      regionId: regionId,
      downloadedBytes: downloadedBytes,
      completedResources: completedResources,
      status: status,
    );
  }

  @override
  Future<void> upsertRegion(OfflineRegionRecord region) {
    return _regionsDao.upsert(region);
  }
}
