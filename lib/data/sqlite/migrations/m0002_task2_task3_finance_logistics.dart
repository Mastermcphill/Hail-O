import '../migration.dart';

class M0002Task2Task3FinanceLogistics extends Migration {
  const M0002Task2Task3FinanceLogistics();

  @override
  int get version => 2;

  @override
  String get name => 'm0002_task2_task3_finance_logistics';

  @override
  String get checksum => 'm0002_task2_task3_finance_logistics_v1';

  @override
  List<String> get upSql => <String>[
    '''
    CREATE TABLE IF NOT EXISTS moneybox_liquidation_events (
      event_id TEXT PRIMARY KEY,
      owner_id TEXT NOT NULL,
      reason TEXT NOT NULL,
      principal_minor INTEGER NOT NULL DEFAULT 0,
      penalty_minor INTEGER NOT NULL DEFAULT 0,
      harmed_party_id TEXT,
      status TEXT NOT NULL,
      idempotency_scope TEXT NOT NULL,
      idempotency_key TEXT NOT NULL,
      created_at TEXT NOT NULL,
      UNIQUE(idempotency_scope, idempotency_key)
    )
    ''',
    '''
    CREATE TABLE IF NOT EXISTS breakdown_events (
      id TEXT PRIMARY KEY,
      ride_id TEXT NOT NULL,
      old_driver_id TEXT NOT NULL,
      covered_dist_km REAL NOT NULL,
      total_dist_km REAL NOT NULL,
      total_fare_minor INTEGER NOT NULL,
      payable_minor INTEGER NOT NULL,
      old_driver_credit_minor INTEGER NOT NULL,
      remaining_fare_minor INTEGER NOT NULL,
      rescue_offer_minor INTEGER NOT NULL,
      created_at TEXT NOT NULL,
      FOREIGN KEY(ride_id) REFERENCES rides(id)
    )
    ''',
    '''
    CREATE TABLE IF NOT EXISTS safety_events (
      id TEXT PRIMARY KEY,
      ride_id TEXT NOT NULL,
      event_type TEXT NOT NULL,
      payload_json TEXT,
      created_at TEXT NOT NULL,
      FOREIGN KEY(ride_id) REFERENCES rides(id)
    )
    ''',
    '''
    CREATE TABLE IF NOT EXISTS trip_location_samples (
      id INTEGER PRIMARY KEY AUTOINCREMENT,
      ride_id TEXT NOT NULL,
      ts TEXT NOT NULL,
      lat REAL NOT NULL,
      lng REAL NOT NULL,
      distance_from_route_m REAL NOT NULL,
      is_deviating INTEGER NOT NULL CHECK(is_deviating IN (0,1)),
      FOREIGN KEY(ride_id) REFERENCES rides(id)
    )
    ''',
    '''
    CREATE INDEX IF NOT EXISTS idx_moneybox_liq_owner_created
    ON moneybox_liquidation_events(owner_id, created_at DESC)
    ''',
    '''
    CREATE INDEX IF NOT EXISTS idx_breakdown_ride_created
    ON breakdown_events(ride_id, created_at DESC)
    ''',
    '''
    CREATE INDEX IF NOT EXISTS idx_safety_ride_created
    ON safety_events(ride_id, created_at DESC)
    ''',
    '''
    CREATE INDEX IF NOT EXISTS idx_trip_samples_ride_ts
    ON trip_location_samples(ride_id, ts DESC)
    ''',
  ];
}
