import '../migration.dart';

class M0003MapboxOfflineFoundation extends Migration {
  const M0003MapboxOfflineFoundation();

  @override
  int get version => 3;

  @override
  String get name => 'm0003_mapbox_offline_foundation';

  @override
  String get checksum => 'm0003_mapbox_offline_foundation_v1';

  @override
  List<String> get upSql => <String>[
    '''
    CREATE TABLE IF NOT EXISTS offline_regions (
      region_id TEXT PRIMARY KEY,
      name TEXT,
      style_uri TEXT NOT NULL,
      min_zoom REAL NOT NULL,
      max_zoom REAL NOT NULL,
      geometry_json TEXT NOT NULL,
      downloaded_bytes INTEGER NOT NULL DEFAULT 0,
      completed_resources INTEGER NOT NULL DEFAULT 0,
      status TEXT NOT NULL,
      created_at TEXT NOT NULL
    )
    ''',
    '''
    CREATE TABLE IF NOT EXISTS offline_download_events (
      id INTEGER PRIMARY KEY AUTOINCREMENT,
      region_id TEXT NOT NULL,
      ts TEXT NOT NULL,
      progress REAL NOT NULL DEFAULT 0,
      message TEXT,
      FOREIGN KEY(region_id) REFERENCES offline_regions(region_id)
    )
    ''',
    '''
    CREATE TABLE IF NOT EXISTS route_polylines (
      route_id TEXT PRIMARY KEY,
      polyline_json TEXT NOT NULL,
      total_distance_m REAL NOT NULL,
      created_at TEXT NOT NULL
    )
    ''',
    '''
    CREATE INDEX IF NOT EXISTS idx_offline_regions_status_created
    ON offline_regions(status, created_at DESC)
    ''',
    '''
    CREATE INDEX IF NOT EXISTS idx_offline_events_region_ts
    ON offline_download_events(region_id, ts DESC)
    ''',
  ];
}
