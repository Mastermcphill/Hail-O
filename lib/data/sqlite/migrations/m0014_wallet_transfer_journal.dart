import '../migration.dart';

class M0014WalletTransferJournal extends Migration {
  const M0014WalletTransferJournal();

  @override
  int get version => 14;

  @override
  String get name => 'm0014_wallet_transfer_journal';

  @override
  String get checksum => 'm0014_wallet_transfer_journal_v1';

  @override
  List<String> get upSql => <String>[
    '''
    CREATE TABLE IF NOT EXISTS wallet_transfers (
      transfer_id TEXT PRIMARY KEY,
      from_owner_id TEXT NOT NULL,
      from_wallet_type TEXT NOT NULL,
      to_owner_id TEXT NOT NULL,
      to_wallet_type TEXT NOT NULL,
      amount_minor INTEGER NOT NULL CHECK(amount_minor > 0),
      kind TEXT NOT NULL,
      reference_id TEXT NOT NULL,
      idempotency_scope TEXT NOT NULL,
      idempotency_key TEXT NOT NULL,
      created_at TEXT NOT NULL,
      UNIQUE(idempotency_scope, idempotency_key)
    )
    ''',
    '''
    ALTER TABLE wallet_ledger ADD COLUMN transfer_id TEXT
    ''',
    '''
    CREATE INDEX IF NOT EXISTS idx_wallet_transfers_created
    ON wallet_transfers(created_at DESC)
    ''',
    '''
    CREATE INDEX IF NOT EXISTS idx_wallet_transfers_from_owner
    ON wallet_transfers(from_owner_id, from_wallet_type, created_at DESC)
    ''',
    '''
    CREATE INDEX IF NOT EXISTS idx_wallet_transfers_to_owner
    ON wallet_transfers(to_owner_id, to_wallet_type, created_at DESC)
    ''',
    '''
    CREATE INDEX IF NOT EXISTS idx_wallet_ledger_transfer_id
    ON wallet_ledger(transfer_id)
    ''',
    '''
    CREATE INDEX IF NOT EXISTS idx_wallet_ledger_scope_key_guard
    ON wallet_ledger(idempotency_scope, idempotency_key)
    ''',
  ];
}
