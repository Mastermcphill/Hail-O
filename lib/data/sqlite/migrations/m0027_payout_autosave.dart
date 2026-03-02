import '../migration.dart';

class M0027PayoutAutosave extends Migration {
  const M0027PayoutAutosave();

  @override
  int get version => 27;

  @override
  String get name => 'm0027_payout_autosave';

  @override
  String get checksum => 'm0027_payout_autosave_v1';

  @override
  List<String> get upSql => <String>[
    '''
    CREATE TABLE IF NOT EXISTS autosave_plans (
      id INTEGER PRIMARY KEY AUTOINCREMENT,
      user_id TEXT NOT NULL UNIQUE REFERENCES users(id),
      tier INTEGER NOT NULL CHECK(tier BETWEEN 1 AND 4),
      lock_days INTEGER NOT NULL CHECK(lock_days IN (30, 120, 210, 330)),
      autosave_enabled INTEGER NOT NULL DEFAULT 1 CHECK(autosave_enabled IN (0, 1)),
      autosave_percent INTEGER NOT NULL DEFAULT 5 CHECK(autosave_percent BETWEEN 1 AND 30),
      status TEXT NOT NULL CHECK(status IN ('ACTIVE', 'PAUSED', 'MATURED', 'CLOSED')),
      started_at TEXT NOT NULL,
      maturity_at TEXT NOT NULL,
      bonus_rate REAL NOT NULL DEFAULT 0,
      bonus_eligible INTEGER NOT NULL DEFAULT 1 CHECK(bonus_eligible IN (0, 1)),
      bonus_paid_at TEXT,
      total_autosaved_minor INTEGER NOT NULL DEFAULT 0,
      total_bonus_minor INTEGER NOT NULL DEFAULT 0,
      total_exit_fees_minor INTEGER NOT NULL DEFAULT 0,
      main_recipient_code TEXT,
      savings_recipient_code TEXT,
      last_applied_payout_ledger_id TEXT,
      created_at TEXT NOT NULL,
      updated_at TEXT NOT NULL
    )
    ''',
    '''
    CREATE TABLE IF NOT EXISTS autosave_ledger (
      id INTEGER PRIMARY KEY AUTOINCREMENT,
      user_id TEXT NOT NULL REFERENCES users(id),
      plan_id INTEGER NOT NULL REFERENCES autosave_plans(id),
      payout_ledger_id TEXT,
      entry_type TEXT NOT NULL CHECK(
        entry_type IN (
          'PLAN_OPEN',
          'PLAN_CHANGE',
          'AUTOSAVE_SPLIT',
          'BONUS',
          'EXIT_FEE',
          'EXIT_FEE_COLLECTED',
          'PLAN_PAUSE',
          'PLAN_RESUME',
          'PLAN_CLOSE'
        )
      ),
      amount_minor INTEGER NOT NULL,
      reference TEXT NOT NULL UNIQUE,
      meta_json TEXT,
      created_at TEXT NOT NULL
    )
    ''',
    '''
    CREATE TABLE IF NOT EXISTS payout_transfers (
      id INTEGER PRIMARY KEY AUTOINCREMENT,
      user_id TEXT NOT NULL REFERENCES users(id),
      trip_id TEXT,
      payout_ledger_id TEXT,
      kind TEXT NOT NULL CHECK(kind IN ('MAIN', 'SAVINGS', 'BONUS', 'EXIT_FEE')),
      amount_minor INTEGER NOT NULL,
      recipient_code TEXT NOT NULL,
      provider_transfer_code TEXT,
      provider_reference TEXT NOT NULL UNIQUE,
      status TEXT NOT NULL CHECK(status IN ('PENDING', 'SUCCESS', 'FAILED', 'REVERSED')),
      meta_json TEXT,
      created_at TEXT NOT NULL,
      updated_at TEXT NOT NULL
    )
    ''',
    '''
    CREATE INDEX IF NOT EXISTS idx_autosave_plans_status_maturity
    ON autosave_plans(status, maturity_at ASC)
    ''',
    '''
    CREATE INDEX IF NOT EXISTS idx_autosave_ledger_user_created_desc
    ON autosave_ledger(user_id, created_at DESC)
    ''',
    '''
    CREATE INDEX IF NOT EXISTS idx_autosave_ledger_plan_created_desc
    ON autosave_ledger(plan_id, created_at DESC)
    ''',
    '''
    CREATE INDEX IF NOT EXISTS idx_payout_transfers_user_created_desc
    ON payout_transfers(user_id, created_at DESC)
    ''',
    '''
    CREATE INDEX IF NOT EXISTS idx_payout_transfers_payout_kind
    ON payout_transfers(payout_ledger_id, kind, created_at DESC)
    ''',
  ];
}
