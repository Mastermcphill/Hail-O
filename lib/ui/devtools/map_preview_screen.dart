import 'package:flutter/material.dart';

import '../../data/repositories/sqlite_offline_region_repository.dart';
import '../../data/sqlite/dao/offline_download_events_dao.dart';
import '../../data/sqlite/dao/offline_regions_dao.dart';
import '../../data/sqlite/hailo_database.dart';
import '../../domain/models/latlng.dart';
import '../../integrations/location/location_service.dart';
import '../../integrations/mapbox/mapbox_map_widget.dart';

class MapPreviewScreen extends StatefulWidget {
  const MapPreviewScreen({super.key});

  @override
  State<MapPreviewScreen> createState() => _MapPreviewScreenState();
}

class _MapPreviewScreenState extends State<MapPreviewScreen> {
  final HailODatabase _database = HailODatabase();
  final LocationService _locationService = const LocationService();
  int _offlineCount = 0;
  LatLng? _currentLocation;
  bool _simulateOfflineMode = false;

  @override
  void initState() {
    super.initState();
    _loadStats();
    _loadCurrentLocation();
  }

  Future<void> _loadStats() async {
    final db = await _database.open();
    final repository = SqliteOfflineRegionRepository(
      regionsDao: OfflineRegionsDao(db),
      eventsDao: OfflineDownloadEventsDao(db),
    );
    final regions = await repository.listRegions();
    if (!mounted) {
      return;
    }
    setState(() {
      _offlineCount = regions.length;
    });
  }

  Future<void> _loadCurrentLocation() async {
    final current = await _locationService.getCurrentPosition();
    if (!mounted) {
      return;
    }
    setState(() {
      _currentLocation = current;
    });
  }

  @override
  Widget build(BuildContext context) {
    final fallbackCenter =
        _currentLocation ?? const LatLng(latitude: 6.5244, longitude: 3.3792);

    return Scaffold(
      appBar: AppBar(title: const Text('Map Preview')),
      body: Column(
        children: <Widget>[
          Expanded(
            child: MapboxMapWidget(
              initialCenter: fallbackCenter,
              showUserLocation: true,
            ),
          ),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(12),
            color: Colors.black87,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Text(
                  'offline regions available: $_offlineCount',
                  style: const TextStyle(color: Colors.white),
                ),
                Text(
                  _currentLocation == null
                      ? 'current GPS: unavailable'
                      : 'current GPS: ${_currentLocation!.latitude.toStringAsFixed(6)}, '
                            '${_currentLocation!.longitude.toStringAsFixed(6)}',
                  style: const TextStyle(color: Colors.white),
                ),
                const SizedBox(height: 8),
                Row(
                  children: <Widget>[
                    const Text(
                      'simulate offline mode',
                      style: TextStyle(color: Colors.white),
                    ),
                    const Spacer(),
                    Switch(
                      value: _simulateOfflineMode,
                      onChanged: (value) {
                        setState(() {
                          _simulateOfflineMode = value;
                        });
                      },
                    ),
                  ],
                ),
                if (_simulateOfflineMode && _offlineCount == 0)
                  const Text(
                    'Warning: no downloaded region found for offline preview.',
                    style: TextStyle(color: Colors.amber),
                  ),
                Align(
                  alignment: Alignment.centerRight,
                  child: TextButton(
                    onPressed: () async {
                      await _loadStats();
                      await _loadCurrentLocation();
                    },
                    child: const Text('Refresh HUD'),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
