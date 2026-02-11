import '../migration.dart';

class M0011DisputesWorkflow extends Migration {
  const M0011DisputesWorkflow();

  @override
  int get version => 11;

  @override
  String get name => 'm0011_disputes_workflow';

  @override
  String get checksum => 'm0011_disputes_workflow_v1';

  @override
  List<String> get upSql => <String>[
    '''
    CREATE TABLE IF NOT EXISTS disputes (
      id TEXT PRIMARY KEY,
      ride_id TEXT NOT NULL,
      opened_by TEXT NOT NULL,
      status TEXT NOT NULL CHECK(status IN ('open','resolved','closed')),
      reason TEXT NOT NULL,
      created_at TEXT NOT NULL,
      resolved_at TEXT,
      resolver_user_id TEXT,
      resolution_note TEXT,
      refund_minor_total INTEGER NOT NULL DEFAULT 0,
      FOREIGN KEY(ride_id) REFERENCES rides(id),
      FOREIGN KEY(opened_by) REFERENCES users(id)
    )
    ''',
    '''
    CREATE TABLE IF NOT EXISTS dispute_events (
      id TEXT PRIMARY KEY,
      dispute_id TEXT NOT NULL,
      event_type TEXT NOT NULL,
      actor_id TEXT NOT NULL,
      payload_json TEXT NOT NULL,
      idempotency_scope TEXT NOT NULL,
      idempotency_key TEXT NOT NULL,
      created_at TEXT NOT NULL,
      UNIQUE(idempotency_scope, idempotency_key),
      FOREIGN KEY(dispute_id) REFERENCES disputes(id)
    )
    ''',
    '''
    CREATE INDEX IF NOT EXISTS idx_disputes_ride_created
    ON disputes(ride_id, created_at DESC)
    ''',
    '''
    CREATE INDEX IF NOT EXISTS idx_dispute_events_dispute_created
    ON dispute_events(dispute_id, created_at DESC)
    ''',
  ];
}
