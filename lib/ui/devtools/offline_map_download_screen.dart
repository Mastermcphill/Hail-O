import 'package:flutter/material.dart';

import '../../data/repositories/sqlite_offline_region_repository.dart';
import '../../data/sqlite/dao/offline_download_events_dao.dart';
import '../../data/sqlite/dao/offline_regions_dao.dart';
import '../../data/sqlite/hailo_database.dart';
import '../../domain/models/latlng.dart';
import '../../domain/services/offline_region_sync_service.dart';
import '../../integrations/mapbox/offline_mapbox_manager.dart';

class _RegionPreset {
  const _RegionPreset({
    required this.id,
    required this.name,
    required this.bounds,
    this.styleUri = 'mapbox://styles/mapbox/standard',
    this.minZoom = 8,
    this.maxZoom = 16,
  });

  final String id;
  final String name;
  final OfflineRegionBounds bounds;
  final String styleUri;
  final double minZoom;
  final double maxZoom;
}

class OfflineMapDownloadScreen extends StatefulWidget {
  const OfflineMapDownloadScreen({super.key});

  @override
  State<OfflineMapDownloadScreen> createState() =>
      _OfflineMapDownloadScreenState();
}

class _OfflineMapDownloadScreenState extends State<OfflineMapDownloadScreen> {
  static const List<_RegionPreset> _presets = <_RegionPreset>[
    _RegionPreset(
      id: 'lagos_metro',
      name: 'Lagos Metro',
      bounds: OfflineRegionBounds(
        southWest: LatLng(latitude: 6.37, longitude: 3.09),
        northEast: LatLng(latitude: 6.72, longitude: 3.67),
      ),
      styleUri: 'mapbox://styles/mapbox/standard',
      minZoom: 8,
      maxZoom: 16,
    ),
    _RegionPreset(
      id: 'abuja_city',
      name: 'Abuja',
      bounds: OfflineRegionBounds(
        southWest: LatLng(latitude: 8.90, longitude: 7.20),
        northEast: LatLng(latitude: 9.16, longitude: 7.62),
      ),
      styleUri: 'mapbox://styles/mapbox/standard',
      minZoom: 8,
      maxZoom: 16,
    ),
  ];

  final MapboxOfflineMapboxManager _manager = MapboxOfflineMapboxManager();
  late final HailODatabase _database;
  OfflineRegionSyncService? _syncService;
  _RegionPreset _selected = _presets.first;
  String _status = 'idle';
  double _progress = 0;

  @override
  void initState() {
    super.initState();
    _database = HailODatabase();
    _init();
  }

  Future<void> _init() async {
    final db = await _database.open();
    final repository = SqliteOfflineRegionRepository(
      regionsDao: OfflineRegionsDao(db),
      eventsDao: OfflineDownloadEventsDao(db),
    );
    final sync = OfflineRegionSyncService(
      mapboxManager: _manager,
      repository: repository,
    );
    sync.observeAndPersistProgress(regionId: _selected.id);
    setState(() {
      _syncService = sync;
    });

    _manager.observeDownloadProgress(regionId: _selected.id).listen((event) {
      if (!mounted) {
        return;
      }
      setState(() {
        _progress = event.progress;
        _status = event.status;
      });
    });
  }

  @override
  void dispose() {
    _syncService?.dispose();
    super.dispose();
  }

  Future<void> _startDownload() async {
    final sync = _syncService;
    if (sync == null) {
      return;
    }
    setState(() {
      _status = 'downloading';
      _progress = 0;
    });
    try {
      await sync.downloadRegion(
        regionId: _selected.id,
        name: _selected.name,
        bounds: _selected.bounds,
        styleUri: _selected.styleUri,
        minZoom: _selected.minZoom,
        maxZoom: _selected.maxZoom,
      );
      if (!mounted) {
        return;
      }
      setState(() {
        _status = 'completed';
        _progress = 1;
      });
    } catch (error) {
      if (!mounted) {
        return;
      }
      setState(() {
        _status = 'failed: $error';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Offline Download')),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            DropdownButton<_RegionPreset>(
              value: _selected,
              isExpanded: true,
              items: _presets
                  .map(
                    (preset) => DropdownMenuItem<_RegionPreset>(
                      value: preset,
                      child: Text(preset.name),
                    ),
                  )
                  .toList(growable: false),
              onChanged: (value) {
                if (value == null) {
                  return;
                }
                setState(() {
                  _selected = value;
                });
              },
            ),
            const SizedBox(height: 12),
            LinearProgressIndicator(value: _progress == 0 ? null : _progress),
            const SizedBox(height: 8),
            Text('status: $_status'),
            const SizedBox(height: 16),
            FilledButton(
              onPressed: _syncService == null ? null : _startDownload,
              child: const Text('Start Download'),
            ),
          ],
        ),
      ),
    );
  }
}
