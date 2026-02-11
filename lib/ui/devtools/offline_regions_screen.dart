import 'package:flutter/material.dart';

import '../../data/repositories/sqlite_offline_region_repository.dart';
import '../../data/sqlite/dao/offline_download_events_dao.dart';
import '../../data/sqlite/dao/offline_regions_dao.dart';
import '../../data/sqlite/hailo_database.dart';
import '../../domain/models/offline_region_record.dart';
import '../../domain/services/offline_region_sync_service.dart';
import '../../integrations/mapbox/offline_mapbox_manager.dart';

class OfflineRegionsScreen extends StatefulWidget {
  const OfflineRegionsScreen({super.key});

  @override
  State<OfflineRegionsScreen> createState() => _OfflineRegionsScreenState();
}

class _OfflineRegionsScreenState extends State<OfflineRegionsScreen> {
  final HailODatabase _database = HailODatabase();
  final MapboxOfflineMapboxManager _mapboxManager =
      MapboxOfflineMapboxManager();
  SqliteOfflineRegionRepository? _repository;
  OfflineRegionSyncService? _syncService;
  List<OfflineRegionRecord> _regions = <OfflineRegionRecord>[];

  @override
  void initState() {
    super.initState();
    _init();
  }

  Future<void> _init() async {
    final db = await _database.open();
    final repository = SqliteOfflineRegionRepository(
      regionsDao: OfflineRegionsDao(db),
      eventsDao: OfflineDownloadEventsDao(db),
    );
    final syncService = OfflineRegionSyncService(
      mapboxManager: _mapboxManager,
      repository: repository,
    );
    setState(() {
      _repository = repository;
      _syncService = syncService;
    });
    await _refresh();
  }

  Future<void> _refresh() async {
    final repository = _repository;
    if (repository == null) {
      return;
    }
    final regions = await repository.listRegions();
    if (!mounted) {
      return;
    }
    setState(() {
      _regions = regions;
    });
  }

  Future<void> _deleteRegion(String regionId) async {
    final syncService = _syncService;
    if (syncService == null) {
      return;
    }
    await syncService.deleteRegion(regionId);
    await _refresh();
  }

  @override
  void dispose() {
    _syncService?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Offline Regions'),
        actions: <Widget>[
          IconButton(onPressed: _refresh, icon: const Icon(Icons.refresh)),
        ],
      ),
      body: ListView.builder(
        itemCount: _regions.length,
        itemBuilder: (context, index) {
          final region = _regions[index];
          return ListTile(
            title: Text(region.name.isEmpty ? region.regionId : region.name),
            subtitle: Text(
              'status=${region.status} bytes=${region.downloadedBytes}',
            ),
            trailing: IconButton(
              icon: const Icon(Icons.delete_outline),
              onPressed: () => _deleteRegion(region.regionId),
            ),
          );
        },
      ),
    );
  }
}
