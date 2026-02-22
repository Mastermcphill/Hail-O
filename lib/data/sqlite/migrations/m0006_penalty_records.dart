import '../migration.dart';

class M0006PenaltyRecords extends Migration {
  const M0006PenaltyRecords();

  @override
  int get version => 6;

  @override
  String get name => 'm0006_penalty_records';

  @override
  String get checksum => 'm0006_penalty_records_v2';

  @override
  List<String> get upSql => <String>[
    '''
    CREATE TABLE IF NOT EXISTS penalty_records (
      id TEXT PRIMARY KEY,
      ride_id TEXT,
      user_id TEXT NOT NULL,
      amount_minor INTEGER NOT NULL DEFAULT 0,
      rule_code TEXT NOT NULL,
      status TEXT NOT NULL CHECK(status IN ('assessed','collected')),
      created_at TEXT NOT NULL,
      idempotency_scope TEXT NOT NULL,
      idempotency_key TEXT NOT NULL,
      ride_type TEXT,
      total_fare_minor INTEGER,
      collected_to_owner_id TEXT,
      collected_to_wallet_type TEXT,
      UNIQUE(idempotency_scope, idempotency_key),
      FOREIGN KEY(ride_id) REFERENCES rides(id),
      FOREIGN KEY(user_id) REFERENCES users(id)
    )
    ''',
    '''
    CREATE INDEX IF NOT EXISTS idx_penalty_records_ride_created
    ON penalty_records(ride_id, created_at DESC)
    ''',
    '''
    CREATE INDEX IF NOT EXISTS idx_penalty_records_user_created
    ON penalty_records(user_id, created_at DESC)
    ''',
  ];
}
