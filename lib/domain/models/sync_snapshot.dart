class SyncSnapshot {
  const SyncSnapshot({
    required this.schemaVersion,
    required this.exportedAtUtc,
    required this.tables,
  });

  final int schemaVersion;
  final DateTime exportedAtUtc;
  final Map<String, List<Map<String, Object?>>> tables;

  Map<String, Object?> toMap() {
    return <String, Object?>{
      'schema_version': schemaVersion,
      'exported_at': exportedAtUtc.toUtc().toIso8601String(),
      'tables': tables.map(
        (key, value) =>
            MapEntry<String, Object?>(key, value.map((row) => row).toList()),
      ),
    };
  }

  factory SyncSnapshot.fromMap(Map<String, Object?> map) {
    final tableRaw =
        map['tables'] as Map<String, Object?>? ?? <String, Object?>{};
    final tables = <String, List<Map<String, Object?>>>{};
    for (final entry in tableRaw.entries) {
      final rows = entry.value as List<dynamic>? ?? <dynamic>[];
      tables[entry.key] = rows
          .whereType<Map>()
          .map(
            (row) => row.map(
              (key, value) => MapEntry<String, Object?>(key.toString(), value),
            ),
          )
          .toList(growable: false);
    }
    return SyncSnapshot(
      schemaVersion: (map['schema_version'] as num?)?.toInt() ?? 0,
      exportedAtUtc: DateTime.parse(map['exported_at'] as String).toUtc(),
      tables: tables,
    );
  }
}
