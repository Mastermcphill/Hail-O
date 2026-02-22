class ReconciliationAnomaly {
  const ReconciliationAnomaly({
    required this.id,
    required this.runId,
    required this.entityType,
    required this.entityId,
    required this.severity,
    required this.createdAt,
    this.expectedMinor,
    this.actualMinor,
    this.details,
    this.resolvedAt,
  });

  final String id;
  final String runId;
  final String entityType;
  final String entityId;
  final int? expectedMinor;
  final int? actualMinor;
  final String severity;
  final String? details;
  final DateTime createdAt;
  final DateTime? resolvedAt;

  Map<String, Object?> toMap() {
    return <String, Object?>{
      'id': id,
      'run_id': runId,
      'entity_type': entityType,
      'entity_id': entityId,
      'expected_minor': expectedMinor,
      'actual_minor': actualMinor,
      'severity': severity,
      'details': details,
      'created_at': createdAt.toUtc().toIso8601String(),
      'resolved_at': resolvedAt?.toUtc().toIso8601String(),
    };
  }

  factory ReconciliationAnomaly.fromMap(Map<String, Object?> map) {
    final resolvedAt = map['resolved_at'] as String?;
    return ReconciliationAnomaly(
      id: map['id'] as String,
      runId: map['run_id'] as String,
      entityType: map['entity_type'] as String,
      entityId: map['entity_id'] as String,
      expectedMinor: (map['expected_minor'] as num?)?.toInt(),
      actualMinor: (map['actual_minor'] as num?)?.toInt(),
      severity: map['severity'] as String,
      details: map['details'] as String?,
      createdAt: DateTime.parse(map['created_at'] as String).toUtc(),
      resolvedAt: resolvedAt == null
          ? null
          : DateTime.parse(resolvedAt).toUtc(),
    );
  }
}
