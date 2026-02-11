import '../../domain/models/offline_download_event.dart';
import '../../domain/models/offline_region_record.dart';

abstract class OfflineRegionRepository {
  Future<void> upsertRegion(OfflineRegionRecord region);
  Future<void> updateRegionProgress({
    required String regionId,
    required int downloadedBytes,
    required int completedResources,
    required String status,
  });
  Future<OfflineRegionRecord?> getRegion(String regionId);
  Future<List<OfflineRegionRecord>> listRegions();
  Future<void> deleteRegion(String regionId);

  Future<int> appendDownloadEvent(OfflineDownloadEvent event);
  Future<List<OfflineDownloadEvent>> listDownloadEvents(String regionId);
}
