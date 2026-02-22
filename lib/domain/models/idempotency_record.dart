enum IdempotencyStatus {
  claimed('claimed'),
  success('success'),
  failed('failed');

  const IdempotencyStatus(this.dbValue);

  final String dbValue;

  static IdempotencyStatus fromDbValue(String value) {
    return IdempotencyStatus.values.firstWhere(
      (status) => status.dbValue == value,
      orElse: () => IdempotencyStatus.claimed,
    );
  }
}

class IdempotencyRecord {
  const IdempotencyRecord({
    required this.scope,
    required this.key,
    required this.status,
    required this.createdAt,
    required this.updatedAt,
    this.requestHash,
    this.resultHash,
    this.errorCode,
  });

  final String scope;
  final String key;
  final String? requestHash;
  final IdempotencyStatus status;
  final String? resultHash;
  final String? errorCode;
  final DateTime createdAt;
  final DateTime updatedAt;

  bool get isTerminal =>
      status == IdempotencyStatus.success || status == IdempotencyStatus.failed;

  Map<String, Object?> toMap() {
    return <String, Object?>{
      'scope': scope,
      'key': key,
      'request_hash': requestHash,
      'status': status.dbValue,
      'result_hash': resultHash,
      'error_code': errorCode,
      'created_at': createdAt.toUtc().toIso8601String(),
      'updated_at': updatedAt.toUtc().toIso8601String(),
    };
  }

  factory IdempotencyRecord.fromMap(Map<String, Object?> map) {
    return IdempotencyRecord(
      scope: map['scope'] as String,
      key: map['key'] as String,
      requestHash: map['request_hash'] as String?,
      status: IdempotencyStatus.fromDbValue(map['status'] as String),
      resultHash: map['result_hash'] as String?,
      errorCode: map['error_code'] as String?,
      createdAt: DateTime.parse(map['created_at'] as String).toUtc(),
      updatedAt: DateTime.parse(map['updated_at'] as String).toUtc(),
    );
  }
}
