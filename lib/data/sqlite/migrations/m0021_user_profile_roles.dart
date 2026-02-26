import '../migration.dart';

class M0021UserProfileRoles extends Migration {
  const M0021UserProfileRoles();

  @override
  int get version => 21;

  @override
  String get name => 'm0021_user_profile_roles';

  @override
  String get checksum => 'm0021_user_profile_roles_v1';

  @override
  List<String> get upSql => <String>[
    '''
    CREATE TABLE IF NOT EXISTS user_profiles (
      user_id TEXT PRIMARY KEY,
      display_name TEXT,
      email TEXT,
      avatar_url TEXT,
      updated_at TEXT NOT NULL,
      FOREIGN KEY(user_id) REFERENCES users(id)
    )
    ''',
    '''
    CREATE TABLE IF NOT EXISTS user_roles (
      user_id TEXT NOT NULL,
      role TEXT NOT NULL CHECK(role IN ('user', 'admin', 'merchant', 'driver', 'inspector')),
      UNIQUE(user_id, role),
      FOREIGN KEY(user_id) REFERENCES users(id)
    )
    ''',
    '''
    CREATE INDEX IF NOT EXISTS idx_user_roles_user_id
    ON user_roles(user_id)
    ''',
    '''
    INSERT OR IGNORE INTO user_profiles(user_id, display_name, email, avatar_url, updated_at)
    SELECT
      id,
      display_name,
      email,
      NULL,
      updated_at
    FROM users
    ''',
    '''
    INSERT OR IGNORE INTO user_roles(user_id, role)
    SELECT id, 'user'
    FROM users
    ''',
    '''
    INSERT OR IGNORE INTO user_roles(user_id, role)
    SELECT
      id,
      CASE
        WHEN role = 'admin' THEN 'admin'
        WHEN role = 'driver' THEN 'driver'
        WHEN role = 'fleet_owner' THEN 'merchant'
        ELSE 'user'
      END
    FROM users
    ''',
  ];
}
