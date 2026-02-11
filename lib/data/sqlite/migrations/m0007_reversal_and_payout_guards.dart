import '../migration.dart';

class M0007ReversalAndPayoutGuards extends Migration {
  const M0007ReversalAndPayoutGuards();

  @override
  int get version => 7;

  @override
  String get name => 'm0007_reversal_and_payout_guards';

  @override
  String get checksum => 'm0007_reversal_and_payout_guards_v1';

  @override
  List<String> get upSql => <String>[
    '''
    CREATE TABLE IF NOT EXISTS wallet_reversals (
      id TEXT PRIMARY KEY,
      original_ledger_id INTEGER NOT NULL,
      reversal_ledger_id INTEGER NOT NULL,
      requested_by_user_id TEXT NOT NULL,
      reason TEXT NOT NULL,
      idempotency_scope TEXT NOT NULL,
      idempotency_key TEXT NOT NULL,
      created_at TEXT NOT NULL,
      UNIQUE(original_ledger_id),
      UNIQUE(idempotency_scope, idempotency_key),
      FOREIGN KEY(original_ledger_id) REFERENCES wallet_ledger(id),
      FOREIGN KEY(reversal_ledger_id) REFERENCES wallet_ledger(id),
      FOREIGN KEY(requested_by_user_id) REFERENCES users(id)
    )
    ''',
    '''
    CREATE INDEX IF NOT EXISTS idx_wallet_reversals_created
    ON wallet_reversals(created_at DESC)
    ''',
    '''
    CREATE UNIQUE INDEX IF NOT EXISTS idx_payout_records_escrow_once
    ON payout_records(escrow_id)
    ''',
  ];
}
