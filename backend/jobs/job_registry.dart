import 'job.dart';

typedef QueueJobHandler = Future<void> Function(QueueJob job);

class QueueJobRegistry {
  final Map<String, QueueJobHandler> _handlers = <String, QueueJobHandler>{};

  void register(String type, QueueJobHandler handler) {
    final normalizedType = type.trim();
    if (normalizedType.isEmpty) {
      throw ArgumentError.value(type, 'type', 'Job type is required');
    }
    _handlers[normalizedType] = handler;
  }

  QueueJobHandler? lookup(String type) {
    return _handlers[type.trim()];
  }

  bool supports(String type) => lookup(type) != null;
}

