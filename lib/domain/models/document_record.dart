enum DocumentType {
  passport('passport'),
  ecowasId('ecowas_id'),
  other('other');

  const DocumentType(this.dbValue);

  final String dbValue;

  static DocumentType fromDbValue(String value) {
    return DocumentType.values.firstWhere(
      (type) => type.dbValue == value,
      orElse: () => DocumentType.other,
    );
  }
}

class DocumentRecord {
  const DocumentRecord({
    required this.id,
    required this.userId,
    required this.docType,
    required this.fileRef,
    required this.verified,
    this.status = 'verified',
    this.country,
    this.expiresAt,
    this.verifiedAt,
    required this.createdAt,
    required this.updatedAt,
  });

  final String id;
  final String userId;
  final DocumentType docType;
  final String fileRef;
  final bool verified;
  final String status;
  final String? country;
  final DateTime? expiresAt;
  final DateTime? verifiedAt;
  final DateTime createdAt;
  final DateTime updatedAt;

  Map<String, Object?> toMap() {
    return <String, Object?>{
      'id': id,
      'user_id': userId,
      'doc_type': docType.dbValue,
      'file_ref': fileRef,
      'verified': verified ? 1 : 0,
      'status': status,
      'country': country,
      'expires_at': expiresAt?.toUtc().toIso8601String(),
      'verified_at': verifiedAt?.toUtc().toIso8601String(),
      'created_at': createdAt.toUtc().toIso8601String(),
      'updated_at': updatedAt.toUtc().toIso8601String(),
    };
  }

  factory DocumentRecord.fromMap(Map<String, Object?> map) {
    DateTime? parseNullable(String key) {
      final raw = map[key] as String?;
      return raw == null ? null : DateTime.parse(raw).toUtc();
    }

    return DocumentRecord(
      id: map['id'] as String,
      userId: map['user_id'] as String,
      docType: DocumentType.fromDbValue(map['doc_type'] as String),
      fileRef: map['file_ref'] as String,
      verified: ((map['verified'] as num?)?.toInt() ?? 0) == 1,
      status: (map['status'] as String?) ?? 'verified',
      country: map['country'] as String?,
      expiresAt: parseNullable('expires_at'),
      verifiedAt: parseNullable('verified_at'),
      createdAt: DateTime.parse(map['created_at'] as String).toUtc(),
      updatedAt: DateTime.parse(map['updated_at'] as String).toUtc(),
    );
  }
}
