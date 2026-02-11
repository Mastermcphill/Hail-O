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
    required this.createdAt,
    required this.updatedAt,
  });

  final String id;
  final String userId;
  final DocumentType docType;
  final String fileRef;
  final bool verified;
  final DateTime createdAt;
  final DateTime updatedAt;

  Map<String, Object?> toMap() {
    return <String, Object?>{
      'id': id,
      'user_id': userId,
      'doc_type': docType.dbValue,
      'file_ref': fileRef,
      'verified': verified ? 1 : 0,
      'created_at': createdAt.toUtc().toIso8601String(),
      'updated_at': updatedAt.toUtc().toIso8601String(),
    };
  }

  factory DocumentRecord.fromMap(Map<String, Object?> map) {
    return DocumentRecord(
      id: map['id'] as String,
      userId: map['user_id'] as String,
      docType: DocumentType.fromDbValue(map['doc_type'] as String),
      fileRef: map['file_ref'] as String,
      verified: ((map['verified'] as num?)?.toInt() ?? 0) == 1,
      createdAt: DateTime.parse(map['created_at'] as String).toUtc(),
      updatedAt: DateTime.parse(map['updated_at'] as String).toUtc(),
    );
  }
}
