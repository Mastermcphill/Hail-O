enum TimelineEventStatus {
  pending('pending'),
  success('success'),
  warning('warning'),
  error('error'),
  ok('ok');

  const TimelineEventStatus(this.value);
  final String value;

  static TimelineEventStatus fromValue(String value) {
    final normalized = value.trim().toLowerCase();
    for (final status in TimelineEventStatus.values) {
      if (status.value == normalized) {
        return status;
      }
    }
    return TimelineEventStatus.pending;
  }
}

class TimelineEvent {
  TimelineEvent({
    String? id,
    required this.title,
    required this.description,
    DateTime? occurredAt,
    DateTime? timestamp,
    Object? status,
    TimelineEventStatus? statusValue,
    String? type,
    this.cursor,
  }) : occurredAt = _resolveOccurredAt(
         occurredAt: occurredAt,
         timestamp: timestamp,
       ),
       status = _normalizeStatus(status ?? statusValue),
       type = _string(type),
       id = _resolveId(
         id: id,
         type: type,
         timestamp: _resolveOccurredAt(
           occurredAt: occurredAt,
           timestamp: timestamp,
         ),
       );

  final String id;
  final String title;
  final String description;
  final DateTime occurredAt;
  final String status;
  final String type;
  final String? cursor;

  DateTime? get timestamp => occurredAt;
  TimelineEventStatus get statusValue => TimelineEventStatus.fromValue(status);

  factory TimelineEvent.fromMap(Map<String, dynamic> map) {
    final occurredAtRaw = _string(
      map['occurred_at'],
      fallback: _string(map['timestamp']),
    );
    final occurredAt =
        DateTime.tryParse(occurredAtRaw)?.toUtc() ?? DateTime.now().toUtc();
    final id = _string(map['id'], fallback: _string(map['cursor']));
    final type = _string(map['type'], fallback: _string(map['title']));
    return TimelineEvent(
      id: id.isEmpty ? '${type}_$occurredAtRaw' : id,
      title: _string(map['title'], fallback: type),
      description: _string(map['description']),
      occurredAt: occurredAt,
      status: _string(
        map['status'],
        fallback: map['state']?.toString() ?? 'pending',
      ),
      type: type,
      cursor: _nullableString(map['cursor']),
    );
  }

  factory TimelineEvent.fromJson(Map<String, dynamic> json) =>
      TimelineEvent.fromMap(json);

  Map<String, dynamic> toMap() {
    return <String, dynamic>{
      'id': id,
      'type': type,
      'title': title,
      'description': description,
      'occurred_at': occurredAt.toUtc().toIso8601String(),
      'status': status,
      'cursor': cursor,
    };
  }

  Map<String, dynamic> toJson() => toMap();
}

typedef MarketplaceTimelineEvent = TimelineEvent;

DateTime _resolveOccurredAt({DateTime? occurredAt, DateTime? timestamp}) {
  final resolved = occurredAt ?? timestamp;
  if (resolved == null) {
    return DateTime.fromMillisecondsSinceEpoch(0, isUtc: true);
  }
  return resolved.toUtc();
}

String _resolveId({
  required String? id,
  required String? type,
  required DateTime timestamp,
}) {
  final normalizedId = _string(id);
  if (normalizedId.isNotEmpty) {
    return normalizedId;
  }
  final normalizedType = _string(type);
  final ts = timestamp.toIso8601String();
  if (normalizedType.isNotEmpty) {
    return '$normalizedType:$ts';
  }
  return ts;
}

String _normalizeStatus(Object? value) {
  if (value is TimelineEventStatus) {
    return value.value;
  }
  if (value == null) {
    return TimelineEventStatus.pending.value;
  }
  return TimelineEventStatus.fromValue(value.toString()).value;
}

String _string(Object? value, {String fallback = ''}) {
  if (value is String) {
    final trimmed = value.trim();
    if (trimmed.isNotEmpty) {
      return trimmed;
    }
  }
  return fallback;
}

String? _nullableString(Object? value) {
  final normalized = _string(value);
  if (normalized.isEmpty) {
    return null;
  }
  return normalized;
}
