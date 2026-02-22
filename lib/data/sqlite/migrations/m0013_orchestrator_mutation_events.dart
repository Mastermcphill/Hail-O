import '../migration.dart';

class M0013OrchestratorMutationEvents extends Migration {
  const M0013OrchestratorMutationEvents();

  @override
  int get version => 13;

  @override
  String get name => 'm0013_orchestrator_mutation_events';

  @override
  String get checksum => 'm0013_orchestrator_mutation_events_v1';

  @override
  List<String> get upSql => <String>[
    '''
    CREATE TABLE IF NOT EXISTS escrow_events (
      id TEXT PRIMARY KEY,
      escrow_id TEXT NOT NULL,
      ride_id TEXT NOT NULL,
      event_type TEXT NOT NULL,
      actor_id TEXT,
      payload_json TEXT NOT NULL,
      idempotency_scope TEXT NOT NULL,
      idempotency_key TEXT NOT NULL,
      created_at TEXT NOT NULL,
      UNIQUE(idempotency_scope, idempotency_key),
      FOREIGN KEY(escrow_id) REFERENCES escrow_holds(id),
      FOREIGN KEY(ride_id) REFERENCES rides(id)
    )
    ''',
    '''
    CREATE INDEX IF NOT EXISTS idx_escrow_events_escrow_created
    ON escrow_events(escrow_id, created_at DESC)
    ''',
    '''
    CREATE INDEX IF NOT EXISTS idx_escrow_events_ride_event
    ON escrow_events(ride_id, event_type)
    ''',
    '''
    CREATE TABLE IF NOT EXISTS wallet_events (
      id TEXT PRIMARY KEY,
      owner_id TEXT NOT NULL,
      wallet_type TEXT NOT NULL,
      event_type TEXT NOT NULL,
      payload_json TEXT NOT NULL,
      idempotency_scope TEXT NOT NULL,
      idempotency_key TEXT NOT NULL,
      created_at TEXT NOT NULL,
      UNIQUE(idempotency_scope, idempotency_key)
    )
    ''',
    '''
    CREATE INDEX IF NOT EXISTS idx_wallet_events_owner_created
    ON wallet_events(owner_id, wallet_type, created_at DESC)
    ''',
    '''
    CREATE INDEX IF NOT EXISTS idx_wallet_events_owner_event
    ON wallet_events(owner_id, event_type)
    ''',
  ];
}
