enum TimelineEventStatus {
  pending,
  success,
  warning,
  failed;

  static TimelineEventStatus fromString(String value) {
    final normalized = value.trim().toLowerCase();
    switch (normalized) {
      case 'success':
        return TimelineEventStatus.success;
      case 'warning':
        return TimelineEventStatus.warning;
      case 'failed':
      case 'error':
        return TimelineEventStatus.failed;
      case 'pending':
      default:
        return TimelineEventStatus.pending;
    }
  }
}

class TimelineEvent {
  const TimelineEvent({
    required this.id,
    required this.title,
    required this.description,
    required this.occurredAt,
    required this.status,
  });

  final String id;
  final String title;
  final String description;
  final DateTime occurredAt;
  final TimelineEventStatus status;

  factory TimelineEvent.fromMap(Map<String, dynamic> map) {
    final occurredRaw = _readString(map['occurred_at']);
    return TimelineEvent(
      id: _readString(map['id']),
      title: _readString(map['title']),
      description: _readString(map['description']),
      occurredAt:
          DateTime.tryParse(occurredRaw)?.toUtc() ?? DateTime.now().toUtc(),
      status: TimelineEventStatus.fromString(_readString(map['status'])),
    );
  }

  Map<String, dynamic> toMap() {
    return <String, dynamic>{
      'id': id,
      'title': title,
      'description': description,
      'occurred_at': occurredAt.toUtc().toIso8601String(),
      'status': status.name,
    };
  }
}

String _readString(Object? value) {
  if (value is String) {
    return value.trim();
  }
  return '';
}
