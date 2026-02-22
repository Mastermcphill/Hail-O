import '../migration.dart';

class M0018AuthCredentials extends Migration {
  const M0018AuthCredentials();

  @override
  int get version => 18;

  @override
  String get name => 'm0018_auth_credentials';

  @override
  String get checksum => 'm0018_auth_credentials_v1';

  @override
  List<String> get upSql => <String>[
    '''
    CREATE TABLE IF NOT EXISTS auth_credentials (
      user_id TEXT PRIMARY KEY,
      email TEXT NOT NULL UNIQUE,
      password_hash TEXT NOT NULL,
      password_algo TEXT NOT NULL DEFAULT 'bcrypt',
      created_at TEXT NOT NULL,
      updated_at TEXT NOT NULL,
      FOREIGN KEY(user_id) REFERENCES users(id)
    )
    ''',
    '''
    CREATE UNIQUE INDEX IF NOT EXISTS idx_auth_credentials_email
    ON auth_credentials(email)
    ''',
  ];
}
