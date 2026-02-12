enum OperationJournalStatus {
  started('STARTED'),
  committed('COMMITTED'),
  rolledBack('ROLLED_BACK'),
  failed('FAILED');

  const OperationJournalStatus(this.dbValue);
  final String dbValue;

  static OperationJournalStatus fromDbValue(String raw) {
    return OperationJournalStatus.values.firstWhere(
      (status) => status.dbValue == raw,
      orElse: () => OperationJournalStatus.failed,
    );
  }
}

class OperationJournalEntry {
  const OperationJournalEntry({
    required this.id,
    required this.opType,
    required this.entityType,
    required this.entityId,
    required this.idempotencyScope,
    required this.idempotencyKey,
    required this.traceId,
    required this.status,
    required this.startedAt,
    required this.updatedAt,
    required this.metadataJson,
    this.lastError,
  });

  final String id;
  final String opType;
  final String entityType;
  final String entityId;
  final String idempotencyScope;
  final String idempotencyKey;
  final String traceId;
  final OperationJournalStatus status;
  final DateTime startedAt;
  final DateTime updatedAt;
  final String metadataJson;
  final String? lastError;

  Map<String, Object?> toMap() {
    return <String, Object?>{
      'id': id,
      'op_type': opType,
      'entity_type': entityType,
      'entity_id': entityId,
      'idempotency_scope': idempotencyScope,
      'idempotency_key': idempotencyKey,
      'trace_id': traceId,
      'status': status.dbValue,
      'started_at': startedAt.toUtc().toIso8601String(),
      'updated_at': updatedAt.toUtc().toIso8601String(),
      'last_error': lastError,
      'metadata_json': metadataJson,
    };
  }

  factory OperationJournalEntry.fromMap(Map<String, Object?> map) {
    return OperationJournalEntry(
      id: map['id'] as String,
      opType: map['op_type'] as String,
      entityType: map['entity_type'] as String,
      entityId: map['entity_id'] as String,
      idempotencyScope: map['idempotency_scope'] as String,
      idempotencyKey: map['idempotency_key'] as String,
      traceId: map['trace_id'] as String,
      status: OperationJournalStatus.fromDbValue(map['status'] as String),
      startedAt: DateTime.parse(map['started_at'] as String).toUtc(),
      updatedAt: DateTime.parse(map['updated_at'] as String).toUtc(),
      lastError: map['last_error'] as String?,
      metadataJson: map['metadata_json'] as String,
    );
  }
}
