import '../migration.dart';

class M0026AnalyticsEvents extends Migration {
  const M0026AnalyticsEvents();

  @override
  int get version => 26;

  @override
  String get name => 'm0026_analytics_events';

  @override
  String get checksum => 'm0026_analytics_events_v1';

  @override
  List<String> get upSql => <String>[
    '''
    CREATE TABLE IF NOT EXISTS analytics_events (
      id TEXT PRIMARY KEY,
      name TEXT NOT NULL,
      user_id TEXT,
      session_id TEXT,
      properties TEXT,
      created_at TEXT NOT NULL
    )
    ''',
    '''
    CREATE INDEX IF NOT EXISTS idx_analytics_events_name_created_desc
    ON analytics_events(name, created_at DESC)
    ''',
    '''
    CREATE INDEX IF NOT EXISTS idx_analytics_events_user_created_desc
    ON analytics_events(user_id, created_at DESC)
    ''',
  ];
}
