import '../migration.dart';

class M0008RideEventsOrchestrator extends Migration {
  const M0008RideEventsOrchestrator();

  @override
  int get version => 8;

  @override
  String get name => 'm0008_ride_events_orchestrator';

  @override
  String get checksum => 'm0008_ride_events_orchestrator_v1';

  @override
  List<String> get upSql => <String>[
    '''
    CREATE TABLE IF NOT EXISTS ride_events (
      id TEXT PRIMARY KEY,
      ride_id TEXT NOT NULL,
      event_type TEXT NOT NULL,
      actor_id TEXT,
      idempotency_scope TEXT NOT NULL,
      idempotency_key TEXT NOT NULL,
      payload_json TEXT NOT NULL,
      created_at TEXT NOT NULL,
      UNIQUE(idempotency_scope, idempotency_key)
    )
    ''',
    '''
    CREATE INDEX IF NOT EXISTS idx_ride_events_ride_created
    ON ride_events(ride_id, created_at DESC)
    ''',
    '''
    CREATE INDEX IF NOT EXISTS idx_ride_events_ride_type
    ON ride_events(ride_id, event_type)
    ''',
  ];
}
