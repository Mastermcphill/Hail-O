class OfflineDownloadEvent {
  const OfflineDownloadEvent({
    this.id,
    required this.regionId,
    required this.ts,
    required this.progress,
    required this.message,
  });

  final int? id;
  final String regionId;
  final DateTime ts;
  final double progress;
  final String message;

  Map<String, Object?> toMap() {
    return <String, Object?>{
      'id': id,
      'region_id': regionId,
      'ts': ts.toUtc().toIso8601String(),
      'progress': progress,
      'message': message,
    };
  }

  factory OfflineDownloadEvent.fromMap(Map<String, Object?> map) {
    return OfflineDownloadEvent(
      id: (map['id'] as num?)?.toInt(),
      regionId: map['region_id'] as String,
      ts: DateTime.parse(map['ts'] as String).toUtc(),
      progress: (map['progress'] as num?)?.toDouble() ?? 0,
      message: map['message'] as String? ?? '',
    );
  }
}
