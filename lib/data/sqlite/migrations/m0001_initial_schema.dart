import '../migration.dart';

class M0001InitialSchema extends Migration {
  const M0001InitialSchema();

  @override
  int get version => 1;

  @override
  String get name => 'm0001_initial_schema';

  @override
  String get checksum => 'm0001_initial_schema_v1';

  @override
  List<String> get upSql => <String>[
    '''
    CREATE TABLE IF NOT EXISTS users (
      id TEXT PRIMARY KEY,
      role TEXT NOT NULL CHECK(role IN ('rider','driver','fleet_owner','admin')),
      email TEXT,
      display_name TEXT,
      gender TEXT,
      tribe TEXT,
      star_rating REAL NOT NULL DEFAULT 0,
      luggage_count INTEGER NOT NULL DEFAULT 0,
      next_of_kin_locked INTEGER NOT NULL DEFAULT 1 CHECK(next_of_kin_locked IN (0,1)),
      cross_border_doc_locked INTEGER NOT NULL DEFAULT 1 CHECK(cross_border_doc_locked IN (0,1)),
      allow_location_off INTEGER NOT NULL DEFAULT 0 CHECK(allow_location_off IN (0,1)),
      is_blocked INTEGER NOT NULL DEFAULT 0 CHECK(is_blocked IN (0,1)),
      disclosure_accepted INTEGER NOT NULL DEFAULT 0 CHECK(disclosure_accepted IN (0,1)),
      created_at TEXT NOT NULL,
      updated_at TEXT NOT NULL
    )
    ''',
    '''
    CREATE TABLE IF NOT EXISTS driver_profiles (
      driver_id TEXT PRIMARY KEY,
      fleet_owner_id TEXT,
      cash_debt_minor INTEGER NOT NULL DEFAULT 0,
      safety_score INTEGER NOT NULL DEFAULT 0,
      status TEXT NOT NULL DEFAULT 'active',
      created_at TEXT NOT NULL,
      updated_at TEXT NOT NULL,
      FOREIGN KEY(driver_id) REFERENCES users(id)
    )
    ''',
    '''
    CREATE TABLE IF NOT EXISTS vehicles (
      id TEXT PRIMARY KEY,
      driver_id TEXT NOT NULL,
      type TEXT NOT NULL CHECK(type IN ('sedan','hatchback','suv','bus')),
      plate_number TEXT,
      seat_count INTEGER NOT NULL,
      is_active INTEGER NOT NULL DEFAULT 1 CHECK(is_active IN (0,1)),
      created_at TEXT NOT NULL,
      updated_at TEXT NOT NULL,
      FOREIGN KEY(driver_id) REFERENCES users(id)
    )
    ''',
    '''
    CREATE TABLE IF NOT EXISTS next_of_kin (
      user_id TEXT PRIMARY KEY,
      full_name TEXT NOT NULL,
      phone TEXT NOT NULL,
      relationship TEXT,
      created_at TEXT NOT NULL,
      updated_at TEXT NOT NULL,
      FOREIGN KEY(user_id) REFERENCES users(id)
    )
    ''',
    '''
    CREATE TABLE IF NOT EXISTS documents (
      id TEXT PRIMARY KEY,
      user_id TEXT NOT NULL,
      doc_type TEXT NOT NULL CHECK(doc_type IN ('passport','ecowas_id','other')),
      file_ref TEXT NOT NULL,
      verified INTEGER NOT NULL DEFAULT 0 CHECK(verified IN (0,1)),
      created_at TEXT NOT NULL,
      updated_at TEXT NOT NULL,
      FOREIGN KEY(user_id) REFERENCES users(id)
    )
    ''',
    '''
    CREATE TABLE IF NOT EXISTS routes (
      id TEXT PRIMARY KEY,
      driver_id TEXT NOT NULL,
      origin TEXT NOT NULL,
      destination TEXT NOT NULL,
      polyline TEXT,
      total_distance_km REAL NOT NULL DEFAULT 0,
      status TEXT NOT NULL DEFAULT 'active',
      created_at TEXT NOT NULL,
      updated_at TEXT NOT NULL,
      FOREIGN KEY(driver_id) REFERENCES users(id)
    )
    ''',
    '''
    CREATE TABLE IF NOT EXISTS route_nodes (
      id TEXT PRIMARY KEY,
      route_id TEXT NOT NULL,
      sequence_no INTEGER NOT NULL,
      label TEXT NOT NULL,
      latitude REAL,
      longitude REAL,
      created_at TEXT NOT NULL,
      FOREIGN KEY(route_id) REFERENCES routes(id),
      UNIQUE(route_id, sequence_no)
    )
    ''',
    '''
    CREATE TABLE IF NOT EXISTS rides (
      id TEXT PRIMARY KEY,
      rider_id TEXT NOT NULL,
      driver_id TEXT,
      route_id TEXT,
      pickup_node_id TEXT,
      dropoff_node_id TEXT,
      trip_scope TEXT NOT NULL CHECK(trip_scope IN ('intra_city','inter_state','cross_country','international')),
      status TEXT NOT NULL,
      bidding_mode INTEGER NOT NULL DEFAULT 1 CHECK(bidding_mode IN (0,1)),
      base_fare_minor INTEGER NOT NULL DEFAULT 0,
      premium_markup_minor INTEGER NOT NULL DEFAULT 0,
      charter_mode INTEGER NOT NULL DEFAULT 0 CHECK(charter_mode IN (0,1)),
      daily_rate_minor INTEGER NOT NULL DEFAULT 0,
      total_fare_minor INTEGER NOT NULL DEFAULT 0,
      connection_fee_minor INTEGER NOT NULL DEFAULT 0,
      connection_fee_paid INTEGER NOT NULL DEFAULT 0 CHECK(connection_fee_paid IN (0,1)),
      bid_accepted_at TEXT,
      connection_fee_deadline_at TEXT,
      connection_fee_paid_at TEXT,
      started_at TEXT,
      arrived_at TEXT,
      cancelled_at TEXT,
      created_at TEXT NOT NULL,
      updated_at TEXT NOT NULL,
      FOREIGN KEY(rider_id) REFERENCES users(id),
      FOREIGN KEY(driver_id) REFERENCES users(id),
      FOREIGN KEY(route_id) REFERENCES routes(id)
    )
    ''',
    '''
    CREATE TABLE IF NOT EXISTS bids_offers (
      id TEXT PRIMARY KEY,
      ride_id TEXT NOT NULL,
      rider_id TEXT NOT NULL,
      driver_id TEXT NOT NULL,
      offered_fare_minor INTEGER NOT NULL,
      status TEXT NOT NULL CHECK(status IN ('pending','accepted','rejected','expired','cancelled')),
      accepted_at TEXT,
      created_at TEXT NOT NULL,
      updated_at TEXT NOT NULL,
      FOREIGN KEY(ride_id) REFERENCES rides(id)
    )
    ''',
    '''
    CREATE TABLE IF NOT EXISTS seats (
      id TEXT PRIMARY KEY,
      ride_id TEXT NOT NULL,
      seat_code TEXT NOT NULL CHECK(seat_code IN ('front_right','back_left','back_middle','back_right')),
      seat_type TEXT NOT NULL CHECK(seat_type IN ('front','window','middle')),
      base_fare_minor INTEGER NOT NULL DEFAULT 0,
      markup_minor INTEGER NOT NULL DEFAULT 0,
      passenger_user_id TEXT,
      assignment_locked INTEGER NOT NULL DEFAULT 1 CHECK(assignment_locked IN (0,1)),
      created_at TEXT NOT NULL,
      updated_at TEXT NOT NULL,
      FOREIGN KEY(ride_id) REFERENCES rides(id),
      UNIQUE(ride_id, seat_code)
    )
    ''',
    '''
    CREATE TABLE IF NOT EXISTS manifests (
      id TEXT PRIMARY KEY,
      ride_id TEXT NOT NULL,
      rider_id TEXT NOT NULL,
      seat_id TEXT,
      status TEXT NOT NULL,
      no_kin_valid INTEGER NOT NULL DEFAULT 0 CHECK(no_kin_valid IN (0,1)),
      doc_valid INTEGER NOT NULL DEFAULT 0 CHECK(doc_valid IN (0,1)),
      created_at TEXT NOT NULL,
      updated_at TEXT NOT NULL,
      FOREIGN KEY(ride_id) REFERENCES rides(id),
      FOREIGN KEY(rider_id) REFERENCES users(id)
    )
    ''',
    '''
    CREATE TABLE IF NOT EXISTS wallets (
      owner_id TEXT NOT NULL,
      wallet_type TEXT NOT NULL CHECK(wallet_type IN ('driver_a','driver_b','driver_c','fleet_owner','platform')),
      balance_minor INTEGER NOT NULL DEFAULT 0,
      reserved_minor INTEGER NOT NULL DEFAULT 0,
      currency TEXT NOT NULL DEFAULT 'NGN',
      updated_at TEXT NOT NULL,
      created_at TEXT NOT NULL,
      PRIMARY KEY(owner_id, wallet_type)
    )
    ''',
    '''
    CREATE TABLE IF NOT EXISTS wallet_ledger (
      id INTEGER PRIMARY KEY AUTOINCREMENT,
      owner_id TEXT NOT NULL,
      wallet_type TEXT NOT NULL CHECK(wallet_type IN ('driver_a','driver_b','driver_c','fleet_owner','platform')),
      direction TEXT NOT NULL CHECK(direction IN ('credit','debit')),
      amount_minor INTEGER NOT NULL CHECK(amount_minor > 0),
      balance_after_minor INTEGER NOT NULL,
      kind TEXT NOT NULL,
      reference_id TEXT NOT NULL,
      idempotency_scope TEXT NOT NULL,
      idempotency_key TEXT NOT NULL,
      created_at TEXT NOT NULL,
      UNIQUE(idempotency_scope, idempotency_key)
    )
    ''',
    '''
    CREATE TABLE IF NOT EXISTS escrow_holds (
      id TEXT PRIMARY KEY,
      ride_id TEXT NOT NULL,
      holder_user_id TEXT NOT NULL,
      amount_minor INTEGER NOT NULL,
      status TEXT NOT NULL CHECK(status IN ('held','released','refunded')),
      release_mode TEXT,
      created_at TEXT NOT NULL,
      released_at TEXT,
      idempotency_scope TEXT,
      idempotency_key TEXT,
      UNIQUE(idempotency_scope, idempotency_key),
      FOREIGN KEY(ride_id) REFERENCES rides(id)
    )
    ''',
    '''
    CREATE TABLE IF NOT EXISTS payouts (
      id TEXT PRIMARY KEY,
      owner_id TEXT NOT NULL,
      wallet_type TEXT NOT NULL,
      amount_minor INTEGER NOT NULL,
      status TEXT NOT NULL,
      created_at TEXT NOT NULL,
      processed_at TEXT,
      idempotency_scope TEXT,
      idempotency_key TEXT,
      UNIQUE(idempotency_scope, idempotency_key)
    )
    ''',
    '''
    CREATE TABLE IF NOT EXISTS penalties (
      id TEXT PRIMARY KEY,
      user_id TEXT NOT NULL,
      penalty_kind TEXT NOT NULL,
      amount_minor INTEGER NOT NULL,
      reason TEXT,
      created_at TEXT NOT NULL,
      idempotency_scope TEXT,
      idempotency_key TEXT,
      UNIQUE(idempotency_scope, idempotency_key)
    )
    ''',
    '''
    CREATE TABLE IF NOT EXISTS referral_codes (
      code TEXT PRIMARY KEY,
      referrer_user_id TEXT NOT NULL,
      is_active INTEGER NOT NULL DEFAULT 1 CHECK(is_active IN (0,1)),
      created_at TEXT NOT NULL,
      updated_at TEXT NOT NULL,
      FOREIGN KEY(referrer_user_id) REFERENCES users(id)
    )
    ''',
    '''
    CREATE TABLE IF NOT EXISTS promo_events (
      id TEXT PRIMARY KEY,
      event_type TEXT NOT NULL,
      user_id TEXT NOT NULL,
      related_user_id TEXT,
      amount_minor INTEGER NOT NULL DEFAULT 0,
      status TEXT NOT NULL,
      created_at TEXT NOT NULL,
      idempotency_scope TEXT,
      idempotency_key TEXT,
      UNIQUE(idempotency_scope, idempotency_key)
    )
    ''',
    '''
    CREATE TABLE IF NOT EXISTS moneybox_accounts (
      owner_id TEXT PRIMARY KEY,
      tier INTEGER NOT NULL CHECK(tier IN (1,2,3,4)),
      status TEXT NOT NULL,
      lock_start TEXT,
      auto_open_date TEXT,
      maturity_date TEXT,
      principal_minor INTEGER NOT NULL DEFAULT 0,
      projected_bonus_minor INTEGER NOT NULL DEFAULT 0,
      expected_at_maturity_minor INTEGER NOT NULL DEFAULT 0,
      autosave_percent INTEGER NOT NULL DEFAULT 0 CHECK(autosave_percent >= 0 AND autosave_percent <= 30),
      bonus_eligible INTEGER NOT NULL DEFAULT 1 CHECK(bonus_eligible IN (0,1)),
      created_at TEXT NOT NULL,
      updated_at TEXT NOT NULL
    )
    ''',
    '''
    CREATE TABLE IF NOT EXISTS moneybox_ledger (
      id INTEGER PRIMARY KEY AUTOINCREMENT,
      owner_id TEXT NOT NULL,
      entry_type TEXT NOT NULL,
      amount_minor INTEGER NOT NULL CHECK(amount_minor > 0),
      principal_after_minor INTEGER NOT NULL,
      projected_bonus_after_minor INTEGER NOT NULL,
      expected_after_minor INTEGER NOT NULL,
      source_kind TEXT NOT NULL,
      reference_id TEXT NOT NULL,
      idempotency_scope TEXT NOT NULL,
      idempotency_key TEXT NOT NULL,
      created_at TEXT NOT NULL,
      UNIQUE(idempotency_scope, idempotency_key)
    )
    ''',
    '''
    CREATE TABLE IF NOT EXISTS idempotency_keys (
      scope TEXT NOT NULL,
      key TEXT NOT NULL,
      request_hash TEXT,
      status TEXT NOT NULL CHECK(status IN ('claimed','success','failed')),
      result_hash TEXT,
      error_code TEXT,
      created_at TEXT NOT NULL,
      updated_at TEXT NOT NULL,
      PRIMARY KEY(scope, key)
    )
    ''',
    '''
    CREATE TABLE IF NOT EXISTS reconciliation_runs (
      id TEXT PRIMARY KEY,
      started_at TEXT NOT NULL,
      finished_at TEXT,
      status TEXT NOT NULL,
      notes TEXT
    )
    ''',
    '''
    CREATE TABLE IF NOT EXISTS reconciliation_anomalies (
      id TEXT PRIMARY KEY,
      run_id TEXT NOT NULL,
      entity_type TEXT NOT NULL,
      entity_id TEXT NOT NULL,
      expected_minor INTEGER,
      actual_minor INTEGER,
      severity TEXT NOT NULL,
      details TEXT,
      created_at TEXT NOT NULL,
      resolved_at TEXT,
      FOREIGN KEY(run_id) REFERENCES reconciliation_runs(id)
    )
    ''',
    '''
    CREATE INDEX IF NOT EXISTS idx_route_nodes_route_sequence ON route_nodes(route_id, sequence_no)
    ''',
    '''
    CREATE INDEX IF NOT EXISTS idx_wallet_ledger_owner_created ON wallet_ledger(owner_id, wallet_type, created_at DESC)
    ''',
    '''
    CREATE INDEX IF NOT EXISTS idx_moneybox_ledger_owner_created ON moneybox_ledger(owner_id, created_at DESC)
    ''',
    '''
    CREATE INDEX IF NOT EXISTS idx_idempotency_scope_created ON idempotency_keys(scope, created_at DESC)
    ''',
    '''
    CREATE TRIGGER IF NOT EXISTS trg_wallet_ledger_no_update
    BEFORE UPDATE ON wallet_ledger
    BEGIN
      SELECT RAISE(ABORT, 'wallet_ledger_append_only');
    END;
    ''',
    '''
    CREATE TRIGGER IF NOT EXISTS trg_wallet_ledger_no_delete
    BEFORE DELETE ON wallet_ledger
    BEGIN
      SELECT RAISE(ABORT, 'wallet_ledger_append_only');
    END;
    ''',
    '''
    CREATE TRIGGER IF NOT EXISTS trg_moneybox_ledger_no_update
    BEFORE UPDATE ON moneybox_ledger
    BEGIN
      SELECT RAISE(ABORT, 'moneybox_ledger_append_only');
    END;
    ''',
    '''
    CREATE TRIGGER IF NOT EXISTS trg_moneybox_ledger_no_delete
    BEFORE DELETE ON moneybox_ledger
    BEGIN
      SELECT RAISE(ABORT, 'moneybox_ledger_append_only');
    END;
    ''',
  ];
}
