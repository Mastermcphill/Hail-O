import '../migration.dart';

class M0004FleetConfigs extends Migration {
  const M0004FleetConfigs();

  @override
  int get version => 4;

  @override
  String get name => 'm0004_fleet_configs';

  @override
  String get checksum => 'm0004_fleet_configs_v1';

  @override
  List<String> get upSql => <String>[
    '''
    CREATE TABLE IF NOT EXISTS fleet_configs (
      fleet_owner_id TEXT PRIMARY KEY,
      allowance_percent INTEGER NOT NULL DEFAULT 0 CHECK(allowance_percent >= 0 AND allowance_percent <= 100),
      created_at TEXT NOT NULL,
      updated_at TEXT NOT NULL,
      FOREIGN KEY(fleet_owner_id) REFERENCES users(id)
    )
    ''',
  ];
}
