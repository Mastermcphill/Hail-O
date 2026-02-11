import '../migration.dart';

class M0012DocumentsComplianceFields extends Migration {
  const M0012DocumentsComplianceFields();

  @override
  int get version => 12;

  @override
  String get name => 'm0012_documents_compliance_fields';

  @override
  String get checksum => 'm0012_documents_compliance_fields_v1';

  @override
  List<String> get upSql => <String>[
    '''
    ALTER TABLE documents ADD COLUMN status TEXT NOT NULL DEFAULT 'verified'
    ''',
    '''
    ALTER TABLE documents ADD COLUMN country TEXT
    ''',
    '''
    ALTER TABLE documents ADD COLUMN expires_at TEXT
    ''',
    '''
    ALTER TABLE documents ADD COLUMN verified_at TEXT
    ''',
    '''
    UPDATE documents
    SET status = CASE
      WHEN verified = 1 THEN 'verified'
      ELSE 'uploaded'
    END
    WHERE status IS NULL OR status = ''
    ''',
    '''
    UPDATE documents
    SET verified_at = created_at
    WHERE verified = 1 AND verified_at IS NULL
    ''',
    '''
    CREATE INDEX IF NOT EXISTS idx_documents_user_status
    ON documents(user_id, status, doc_type)
    ''',
    '''
    CREATE INDEX IF NOT EXISTS idx_documents_user_expires
    ON documents(user_id, expires_at)
    ''',
  ];
}
