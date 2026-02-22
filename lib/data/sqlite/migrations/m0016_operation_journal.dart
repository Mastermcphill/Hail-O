import '../migration.dart';

class M0016OperationJournal extends Migration {
  const M0016OperationJournal();

  @override
  int get version => 16;

  @override
  String get name => 'm0016_operation_journal';

  @override
  String get checksum => 'm0016_operation_journal_v1';

  @override
  List<String> get upSql => <String>[
    '''
    CREATE TABLE IF NOT EXISTS operation_journal (
      id TEXT PRIMARY KEY,
      op_type TEXT NOT NULL,
      entity_type TEXT NOT NULL,
      entity_id TEXT NOT NULL,
      idempotency_scope TEXT NOT NULL,
      idempotency_key TEXT NOT NULL,
      trace_id TEXT NOT NULL,
      status TEXT NOT NULL CHECK(status IN ('STARTED','COMMITTED','ROLLED_BACK','FAILED')),
      started_at TEXT NOT NULL,
      updated_at TEXT NOT NULL,
      last_error TEXT,
      metadata_json TEXT NOT NULL,
      UNIQUE(idempotency_scope, idempotency_key)
    )
    ''',
    '''
    CREATE INDEX IF NOT EXISTS idx_operation_journal_status_updated
    ON operation_journal(status, updated_at DESC)
    ''',
    '''
    CREATE INDEX IF NOT EXISTS idx_operation_journal_entity_updated
    ON operation_journal(entity_type, entity_id, updated_at DESC)
    ''',
  ];
}
