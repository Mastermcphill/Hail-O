class OfflineRegionRecord {
  const OfflineRegionRecord({
    required this.regionId,
    required this.name,
    required this.styleUri,
    required this.minZoom,
    required this.maxZoom,
    required this.geometryJson,
    required this.downloadedBytes,
    required this.completedResources,
    required this.status,
    required this.createdAt,
  });

  final String regionId;
  final String name;
  final String styleUri;
  final double minZoom;
  final double maxZoom;
  final String geometryJson;
  final int downloadedBytes;
  final int completedResources;
  final String status;
  final DateTime createdAt;

  Map<String, Object?> toMap() {
    return <String, Object?>{
      'region_id': regionId,
      'name': name,
      'style_uri': styleUri,
      'min_zoom': minZoom,
      'max_zoom': maxZoom,
      'geometry_json': geometryJson,
      'downloaded_bytes': downloadedBytes,
      'completed_resources': completedResources,
      'status': status,
      'created_at': createdAt.toUtc().toIso8601String(),
    };
  }

  factory OfflineRegionRecord.fromMap(Map<String, Object?> map) {
    return OfflineRegionRecord(
      regionId: map['region_id'] as String,
      name: map['name'] as String? ?? '',
      styleUri: map['style_uri'] as String? ?? '',
      minZoom: (map['min_zoom'] as num?)?.toDouble() ?? 0,
      maxZoom: (map['max_zoom'] as num?)?.toDouble() ?? 0,
      geometryJson: map['geometry_json'] as String? ?? '{}',
      downloadedBytes: (map['downloaded_bytes'] as num?)?.toInt() ?? 0,
      completedResources: (map['completed_resources'] as num?)?.toInt() ?? 0,
      status: map['status'] as String? ?? 'downloading',
      createdAt: DateTime.parse(map['created_at'] as String).toUtc(),
    );
  }
}
