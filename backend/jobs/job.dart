import 'dart:convert';

class QueueJob {
  const QueueJob({
    required this.id,
    required this.type,
    required this.payload,
    required this.attempts,
    required this.maxAttempts,
    required this.runAtTimestamp,
  });

  final String id;
  final String type;
  final Map<String, Object?> payload;
  final int attempts;
  final int maxAttempts;
  final int runAtTimestamp;

  Map<String, Object?> toJson() {
    return <String, Object?>{
      'id': id,
      'type': type,
      'payload': payload,
      'attempts': attempts,
      'max_attempts': maxAttempts,
      'run_at_timestamp': runAtTimestamp,
    };
  }

  String toJsonString() => jsonEncode(toJson());

  QueueJob copyWith({
    String? id,
    String? type,
    Map<String, Object?>? payload,
    int? attempts,
    int? maxAttempts,
    int? runAtTimestamp,
  }) {
    return QueueJob(
      id: id ?? this.id,
      type: type ?? this.type,
      payload: payload ?? this.payload,
      attempts: attempts ?? this.attempts,
      maxAttempts: maxAttempts ?? this.maxAttempts,
      runAtTimestamp: runAtTimestamp ?? this.runAtTimestamp,
    );
  }

  static QueueJob fromJsonString(String value) {
    final decoded = jsonDecode(value);
    if (decoded is! Map) {
      throw const FormatException('Job payload must be an object');
    }
    final map = decoded.map(
      (key, item) => MapEntry<String, Object?>(key.toString(), item),
    );
    return fromJsonMap(map);
  }

  static QueueJob fromJsonMap(Map<String, Object?> map) {
    final id = (map['id'] as String?)?.trim() ?? '';
    final type = (map['type'] as String?)?.trim() ?? '';
    if (id.isEmpty || type.isEmpty) {
      throw const FormatException('Job id and type are required');
    }
    final payloadRaw = map['payload'];
    final payload = payloadRaw is Map
        ? payloadRaw.map(
            (key, item) => MapEntry<String, Object?>(key.toString(), item),
          )
        : <String, Object?>{};
    final attempts = _toPositiveInt(map['attempts'], fallback: 0);
    final maxAttempts = _toPositiveInt(map['max_attempts'], fallback: 5);
    final runAtTimestamp = _toPositiveInt(
      map['run_at_timestamp'],
      fallback: DateTime.now().toUtc().millisecondsSinceEpoch,
    );
    return QueueJob(
      id: id,
      type: type,
      payload: payload,
      attempts: attempts,
      maxAttempts: maxAttempts <= 0 ? 1 : maxAttempts,
      runAtTimestamp: runAtTimestamp,
    );
  }

  static int _toPositiveInt(Object? value, {required int fallback}) {
    if (value is int) {
      return value;
    }
    if (value is num) {
      return value.toInt();
    }
    if (value is String) {
      final parsed = int.tryParse(value.trim());
      if (parsed != null) {
        return parsed;
      }
    }
    return fallback;
  }
}

class QueueJobTypes {
  static const String processWebhookEvent = 'process_webhook_event';
  static const String reconcilePayment = 'reconcile_payment';
  static const String sendOtp = 'send_otp';
  static const String analyticsFlush = 'analytics_flush';
}

class QueueNames {
  static const String jobs = 'queue:jobs';
  static const String delayed = 'queue:delayed';
  static const String dead = 'queue:dead';
}

