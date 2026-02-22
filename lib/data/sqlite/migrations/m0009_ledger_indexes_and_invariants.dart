import '../migration.dart';

class M0009LedgerIndexesAndInvariants extends Migration {
  const M0009LedgerIndexesAndInvariants();

  @override
  int get version => 9;

  @override
  String get name => 'm0009_ledger_indexes_and_invariants';

  @override
  String get checksum => 'm0009_ledger_indexes_and_invariants_v1';

  @override
  List<String> get upSql => <String>[
    '''
    CREATE INDEX IF NOT EXISTS idx_wallet_ledger_scope_key
    ON wallet_ledger(idempotency_scope, idempotency_key)
    ''',
    '''
    CREATE INDEX IF NOT EXISTS idx_penalty_records_ride_created_guard
    ON penalty_records(ride_id, created_at DESC)
    ''',
  ];
}
