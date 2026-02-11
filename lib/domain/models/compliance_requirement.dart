class ComplianceRequirement {
  const ComplianceRequirement({
    required this.id,
    required this.scope,
    required this.requiredDocsJson,
    required this.createdAt,
    this.fromCountry,
    this.toCountry,
  });

  final String id;
  final String scope;
  final String? fromCountry;
  final String? toCountry;
  final String requiredDocsJson;
  final DateTime createdAt;

  Map<String, Object?> toMap() {
    return <String, Object?>{
      'id': id,
      'scope': scope,
      'from_country': fromCountry,
      'to_country': toCountry,
      'required_docs_json': requiredDocsJson,
      'created_at': createdAt.toUtc().toIso8601String(),
    };
  }

  factory ComplianceRequirement.fromMap(Map<String, Object?> map) {
    return ComplianceRequirement(
      id: map['id'] as String,
      scope: map['scope'] as String,
      fromCountry: map['from_country'] as String?,
      toCountry: map['to_country'] as String?,
      requiredDocsJson: map['required_docs_json'] as String,
      createdAt: DateTime.parse(map['created_at'] as String).toUtc(),
    );
  }
}
