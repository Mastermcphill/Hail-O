import 'dart:async';

import 'package:mapbox_maps_flutter/mapbox_maps_flutter.dart';

import '../../domain/models/latlng.dart';
import 'mapbox_token.dart';

class OfflineRegionBounds {
  const OfflineRegionBounds({required this.southWest, required this.northEast});

  final LatLng southWest;
  final LatLng northEast;
}

class OfflineDownloadProgressUpdate {
  const OfflineDownloadProgressUpdate({
    required this.regionId,
    required this.progress,
    required this.downloadedBytes,
    required this.completedResources,
    required this.status,
    required this.message,
  });

  final String regionId;
  final double progress;
  final int downloadedBytes;
  final int completedResources;
  final String status;
  final String message;
}

abstract class OfflineMapboxManager {
  Future<void> downloadStylePack({required String styleUri});

  Future<void> downloadTileRegion({
    required String regionId,
    required OfflineRegionBounds bounds,
    required double minZoom,
    required double maxZoom,
    required String styleUri,
  });

  Future<List<String>> listDownloadedRegions();

  Future<void> deleteRegion(String regionId);

  Stream<OfflineDownloadProgressUpdate> observeDownloadProgress({
    String? regionId,
  });
}

class MapboxOfflineMapboxManager implements OfflineMapboxManager {
  MapboxOfflineMapboxManager();

  OfflineManager? _offlineManager;
  TileStore? _tileStore;
  final StreamController<OfflineDownloadProgressUpdate> _progressController =
      StreamController<OfflineDownloadProgressUpdate>.broadcast();

  Future<OfflineManager> _getOfflineManager() async {
    if (!isMapboxTokenConfigured) {
      throw StateError('mapbox_token_missing');
    }
    MapboxOptions.setAccessToken(kMapboxAccessToken);
    return _offlineManager ??= await OfflineManager.create();
  }

  Future<TileStore> _getTileStore() async {
    return _tileStore ??= await TileStore.createDefault();
  }

  @override
  Future<void> downloadStylePack({required String styleUri}) async {
    final manager = await _getOfflineManager();
    try {
      await manager.loadStylePack(
        styleUri,
        StylePackLoadOptions(acceptExpired: true),
        (progress) {
          final requiredCount = progress.requiredResourceCount <= 0
              ? 1
              : progress.requiredResourceCount;
          _progressController.add(
            OfflineDownloadProgressUpdate(
              regionId: styleUri,
              progress: progress.completedResourceCount / requiredCount,
              downloadedBytes: progress.completedResourceSize,
              completedResources: progress.completedResourceCount,
              status: 'downloading',
              message: 'style_pack_progress',
            ),
          );
        },
      );
      _progressController.add(
        const OfflineDownloadProgressUpdate(
          regionId: '',
          progress: 1,
          downloadedBytes: 0,
          completedResources: 0,
          status: 'completed',
          message: 'style_pack_completed',
        ),
      );
    } catch (error) {
      _progressController.add(
        OfflineDownloadProgressUpdate(
          regionId: styleUri,
          progress: 0,
          downloadedBytes: 0,
          completedResources: 0,
          status: 'failed',
          message: 'style_pack_error:$error',
        ),
      );
      rethrow;
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
    final tileStore = await _getTileStore();
    final geometry = _polygonGeometry(bounds);

    final options = TileRegionLoadOptions(
      geometry: geometry,
      descriptorsOptions: <TilesetDescriptorOptions>[
        TilesetDescriptorOptions(
          styleURI: styleUri,
          minZoom: minZoom.floor(),
          maxZoom: maxZoom.ceil(),
          stylePackOptions: StylePackLoadOptions(acceptExpired: true),
        ),
      ],
      metadata: <String, Object?>{'region_id': regionId, 'style_uri': styleUri},
      acceptExpired: true,
      networkRestriction: NetworkRestriction.NONE,
    );

    try {
      await tileStore.loadTileRegion(regionId, options, (progress) {
        final requiredCount = progress.requiredResourceCount <= 0
            ? 1
            : progress.requiredResourceCount;
        _progressController.add(
          OfflineDownloadProgressUpdate(
            regionId: regionId,
            progress: progress.completedResourceCount / requiredCount,
            downloadedBytes: progress.completedResourceSize,
            completedResources: progress.completedResourceCount,
            status: 'downloading',
            message: 'tile_region_progress',
          ),
        );
      });

      _progressController.add(
        OfflineDownloadProgressUpdate(
          regionId: regionId,
          progress: 1,
          downloadedBytes: 0,
          completedResources: 0,
          status: 'completed',
          message: 'tile_region_completed',
        ),
      );
    } catch (error) {
      _progressController.add(
        OfflineDownloadProgressUpdate(
          regionId: regionId,
          progress: 0,
          downloadedBytes: 0,
          completedResources: 0,
          status: 'failed',
          message: 'tile_region_error:$error',
        ),
      );
      rethrow;
    }
  }

  @override
  Future<List<String>> listDownloadedRegions() async {
    final tileStore = await _getTileStore();
    final regions = await tileStore.allTileRegions();
    return regions.map((region) => region.id).toList(growable: false);
  }

  @override
  Future<void> deleteRegion(String regionId) async {
    final tileStore = await _getTileStore();
    await tileStore.removeRegion(regionId);
    _progressController.add(
      OfflineDownloadProgressUpdate(
        regionId: regionId,
        progress: 0,
        downloadedBytes: 0,
        completedResources: 0,
        status: 'deleted',
        message: 'tile_region_deleted',
      ),
    );
  }

  @override
  Stream<OfflineDownloadProgressUpdate> observeDownloadProgress({
    String? regionId,
  }) {
    if (regionId == null || regionId.trim().isEmpty) {
      return _progressController.stream;
    }
    return _progressController.stream.where(
      (event) => event.regionId == regionId,
    );
  }

  Map<String, Object?> _polygonGeometry(OfflineRegionBounds bounds) {
    final sw = bounds.southWest;
    final ne = bounds.northEast;
    final nw = LatLng(latitude: ne.latitude, longitude: sw.longitude);
    final se = LatLng(latitude: sw.latitude, longitude: ne.longitude);
    return <String, Object?>{
      'type': 'Polygon',
      'coordinates': <Object?>[
        <Object?>[
          <double>[sw.longitude, sw.latitude],
          <double>[se.longitude, se.latitude],
          <double>[ne.longitude, ne.latitude],
          <double>[nw.longitude, nw.latitude],
          <double>[sw.longitude, sw.latitude],
        ],
      ],
    };
  }
}
