import 'dart:async';

import '../../data/repositories/offline_region_repository.dart';
import '../models/offline_download_event.dart';
import '../models/offline_region_record.dart';
import '../../integrations/mapbox/offline_mapbox_manager.dart';

class OfflineRegionSyncService {
  OfflineRegionSyncService({
    required OfflineMapboxManager mapboxManager,
    required OfflineRegionRepository repository,
    DateTime Function()? nowUtc,
  }) : _mapboxManager = mapboxManager,
       _repository = repository,
       _nowUtc = nowUtc ?? (() => DateTime.now().toUtc());

  final OfflineMapboxManager _mapboxManager;
  final OfflineRegionRepository _repository;
  final DateTime Function() _nowUtc;

  StreamSubscription<OfflineDownloadProgressUpdate>? _progressSubscription;

  void observeAndPersistProgress({String? regionId}) {
    _progressSubscription?.cancel();
    _progressSubscription = _mapboxManager
        .observeDownloadProgress(regionId: regionId)
        .listen((update) async {
          if (update.regionId.trim().isEmpty) {
            return;
          }
          await _repository.updateRegionProgress(
            regionId: update.regionId,
            downloadedBytes: update.downloadedBytes,
            completedResources: update.completedResources,
            status: update.status,
          );
          await _repository.appendDownloadEvent(
            OfflineDownloadEvent(
              regionId: update.regionId,
              ts: _nowUtc(),
              progress: update.progress,
              message: update.message,
            ),
          );
        });
  }

  Future<void> dispose() async {
    await _progressSubscription?.cancel();
    _progressSubscription = null;
  }

  Future<void> downloadRegion({
    required String regionId,
    required String name,
    required OfflineRegionBounds bounds,
    required String styleUri,
    required double minZoom,
    required double maxZoom,
  }) async {
    await _repository.upsertRegion(
      OfflineRegionRecord(
        regionId: regionId,
        name: name,
        styleUri: styleUri,
        minZoom: minZoom,
        maxZoom: maxZoom,
        geometryJson: _boundsJson(bounds),
        downloadedBytes: 0,
        completedResources: 0,
        status: 'downloading',
        createdAt: _nowUtc(),
      ),
    );

    try {
      await _mapboxManager.downloadStylePack(styleUri: styleUri);
      await _mapboxManager.downloadTileRegion(
        regionId: regionId,
        bounds: bounds,
        minZoom: minZoom,
        maxZoom: maxZoom,
        styleUri: styleUri,
      );
      await _repository.updateRegionProgress(
        regionId: regionId,
        downloadedBytes: 0,
        completedResources: 0,
        status: 'completed',
      );
    } catch (error) {
      await _repository.updateRegionProgress(
        regionId: regionId,
        downloadedBytes: 0,
        completedResources: 0,
        status: 'failed',
      );
      await _repository.appendDownloadEvent(
        OfflineDownloadEvent(
          regionId: regionId,
          ts: _nowUtc(),
          progress: 0,
          message: 'download_failed:$error',
        ),
      );
      rethrow;
    }
  }

  Future<void> deleteRegion(String regionId) async {
    try {
      await _mapboxManager.deleteRegion(regionId);
    } catch (_) {
      // Keep local cleanup resilient even when Mapbox token/runtime is unavailable.
    }
    await _repository.deleteRegion(regionId);
  }

  String _boundsJson(OfflineRegionBounds bounds) {
    return '{"sw":{"lat":${bounds.southWest.latitude},"lng":${bounds.southWest.longitude}},'
        '"ne":{"lat":${bounds.northEast.latitude},"lng":${bounds.northEast.longitude}}}';
  }
}
