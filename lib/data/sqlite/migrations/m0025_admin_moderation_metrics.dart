import '../migration.dart';

class M0025AdminModerationMetrics extends Migration {
  const M0025AdminModerationMetrics();

  @override
  int get version => 25;

  @override
  String get name => 'm0025_admin_moderation_metrics';

  @override
  String get checksum => 'm0025_admin_moderation_metrics_v1';

  @override
  List<String> get upSql => <String>[
    '''
    ALTER TABLE users
    ADD COLUMN disabled_at TEXT
    ''',
    '''
    CREATE INDEX IF NOT EXISTS idx_users_disabled_at
    ON users(disabled_at)
    ''',
  ];
}
