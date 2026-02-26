import '../migration.dart';

class M0020PhoneAuth extends Migration {
  const M0020PhoneAuth();

  @override
  int get version => 20;

  @override
  String get name => 'm0020_phone_auth';

  @override
  String get checksum => 'm0020_phone_auth_v1';

  @override
  List<String> get upSql => <String>[
    '''
    ALTER TABLE users
    ADD COLUMN phone_e164 TEXT
    ''',
    '''
    CREATE UNIQUE INDEX IF NOT EXISTS idx_users_phone_e164
    ON users(phone_e164)
    WHERE phone_e164 IS NOT NULL
    ''',
    '''
    CREATE TABLE IF NOT EXISTS otp_challenges (
      id TEXT PRIMARY KEY,
      phone_e164 TEXT NOT NULL,
      code_hash TEXT NOT NULL,
      expires_at TEXT NOT NULL,
      attempts INTEGER NOT NULL DEFAULT 0,
      locked_until TEXT,
      created_at TEXT NOT NULL
    )
    ''',
    '''
    CREATE INDEX IF NOT EXISTS idx_otp_challenges_phone_created_desc
    ON otp_challenges(phone_e164, created_at DESC)
    ''',
    '''
    CREATE INDEX IF NOT EXISTS idx_otp_challenges_expires_at
    ON otp_challenges(expires_at)
    ''',
    '''
    CREATE TABLE IF NOT EXISTS refresh_tokens (
      id TEXT PRIMARY KEY,
      user_id TEXT NOT NULL,
      token_hash TEXT NOT NULL UNIQUE,
      expires_at TEXT NOT NULL,
      revoked_at TEXT,
      created_at TEXT NOT NULL,
      FOREIGN KEY(user_id) REFERENCES users(id)
    )
    ''',
    '''
    CREATE UNIQUE INDEX IF NOT EXISTS idx_refresh_tokens_token_hash
    ON refresh_tokens(token_hash)
    ''',
    '''
    CREATE INDEX IF NOT EXISTS idx_refresh_tokens_user_created_desc
    ON refresh_tokens(user_id, created_at DESC)
    ''',
  ];
}
