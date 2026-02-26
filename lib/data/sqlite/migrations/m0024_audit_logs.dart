import '../migration.dart';

class M0024AuditLogs extends Migration {
  const M0024AuditLogs();

  @override
  int get version => 24;

  @override
  String get name => 'm0024_audit_logs';

  @override
  String get checksum => 'm0024_audit_logs_v1';

  @override
  List<String> get upSql => <String>[
    '''
    CREATE TABLE IF NOT EXISTS audit_logs (
      id TEXT PRIMARY KEY,
      actor_user_id TEXT,
      actor_type TEXT NOT NULL CHECK(actor_type IN ('user', 'admin_token')),
      action TEXT NOT NULL,
      resource_type TEXT NOT NULL,
      resource_id TEXT NOT NULL,
      ip TEXT,
      user_agent TEXT,
      metadata TEXT,
      created_at TEXT NOT NULL
    )
    ''',
    '''
    CREATE INDEX IF NOT EXISTS idx_audit_logs_created_at_desc
    ON audit_logs(created_at DESC)
    ''',
    '''
    CREATE INDEX IF NOT EXISTS idx_audit_logs_actor_user_id
    ON audit_logs(actor_user_id)
    ''',
    '''
    CREATE INDEX IF NOT EXISTS idx_audit_logs_resource
    ON audit_logs(resource_type, resource_id)
    ''',
  ];
}
