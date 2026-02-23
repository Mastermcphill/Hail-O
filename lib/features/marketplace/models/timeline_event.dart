class MarketplaceTimelineEvent {
  const MarketplaceTimelineEvent({
    required this.type,
    required this.title,
    required this.description,
    required this.timestamp,
    required this.status,
    this.cursor,
  });

  final String type;
  final String title;
  final String description;
  final DateTime? timestamp;
  final String status;
  final String? cursor;

  factory MarketplaceTimelineEvent.fromJson(Map<String, dynamic> json) {
    return MarketplaceTimelineEvent(
      type: (json['type'] ?? '').toString(),
      title: (json['title'] ?? '').toString(),
      description: (json['description'] ?? '').toString(),
      timestamp: DateTime.tryParse((json['timestamp'] ?? '').toString()),
      status: (json['status'] ?? 'ok').toString(),
      cursor: json['cursor']?.toString(),
    );
  }

  Map<String, dynamic> toJson() {
    return <String, dynamic>{
      'type': type,
      'title': title,
      'description': description,
      'timestamp': timestamp?.toIso8601String(),
      'status': status,
      'cursor': cursor,
    };
  }
}
