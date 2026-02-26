import 'dart:async';

import 'package:redis/redis.dart';

abstract class RedisQueueClient {
  bool get isConfigured;

  Future<void> connect();

  Future<void> close();

  Future<bool> ping();

  Future<void> enqueue(String queueKey, String payload);

  Future<String?> dequeue(
    String queueKey, {
    Duration timeout = const Duration(seconds: 1),
  });

  Future<void> enqueueDelayed(
    String queueKey,
    String payload, {
    required DateTime runAtUtc,
  });

  Future<List<String>> moveDueDelayed({
    required String delayedQueueKey,
    required String queueKey,
    required DateTime nowUtc,
    int limit = 100,
  });

  Future<void> pushDeadLetter(String queueKey, String payload);

  Future<void> set(String key, String value, {Duration? ttl});

  Future<String?> get(String key);

  Future<void> del(String key);

  Future<int> incrementWithWindow(String key, {required Duration window});
}

class RedisClient implements RedisQueueClient {
  RedisClient({
    required String redisUrl,
    this.connectTimeout = const Duration(seconds: 3),
    this.maxReconnectAttempts = 2,
    void Function(String line)? warningSink,
  }) : _redisUrl = redisUrl.trim(),
       _warningSink = warningSink;

  final String _redisUrl;
  final Duration connectTimeout;
  final int maxReconnectAttempts;
  final void Function(String line)? _warningSink;

  RedisConnection? _connection;
  Command? _command;
  Future<void>? _connectFuture;
  bool _closing = false;

  @override
  bool get isConfigured => _redisUrl.isNotEmpty;

  @override
  Future<void> connect() async {
    if (!isConfigured) {
      throw StateError('REDIS_URL is not configured');
    }
    if (_closing) {
      throw StateError('redis_client_closing');
    }
    if (_command != null) {
      return;
    }
    final inFlight = _connectFuture;
    if (inFlight != null) {
      return inFlight;
    }
    final completer = Completer<void>();
    _connectFuture = completer.future;
    try {
      final uri = Uri.parse(_redisUrl);
      final scheme = uri.scheme.trim().toLowerCase();
      if (scheme != 'redis' && scheme != 'rediss') {
        throw StateError('Unsupported Redis URL scheme: ${uri.scheme}');
      }
      final host = uri.host.trim();
      if (host.isEmpty) {
        throw StateError('REDIS_URL must include host');
      }
      final port = uri.hasPort ? uri.port : 6379;

      final connection = RedisConnection();
      final command =
          (scheme == 'rediss'
                  ? connection.connectSecure(host, port)
                  : connection.connect(host, port))
              .timeout(connectTimeout);

      final connectedCommand = await command;
      await _authenticateIfNeeded(uri, connectedCommand);
      await _selectDatabaseIfNeeded(uri, connectedCommand);
      final ping = await connectedCommand.send_object(<Object>['PING']);
      if ((ping?.toString().toUpperCase() ?? '') != 'PONG') {
        throw StateError('redis_ping_failed');
      }
      _connection = connection;
      _command = connectedCommand;
      completer.complete();
    } catch (error, stackTrace) {
      await _resetConnection();
      completer.completeError(error, stackTrace);
      rethrow;
    } finally {
      _connectFuture = null;
    }
  }

  @override
  Future<void> close() async {
    _closing = true;
    await _resetConnection();
  }

  @override
  Future<bool> ping() async {
    if (!isConfigured) {
      return false;
    }
    try {
      final result = await _execute(
        (command) => command.send_object(<Object>['PING']),
      );
      return (result?.toString().toUpperCase() ?? '') == 'PONG';
    } catch (_) {
      return false;
    }
  }

  @override
  Future<void> enqueue(String queueKey, String payload) {
    return _executeVoid(
      (command) => command.send_object(<Object>['LPUSH', queueKey, payload]),
    );
  }

  @override
  Future<String?> dequeue(
    String queueKey, {
    Duration timeout = const Duration(seconds: 1),
  }) async {
    final timeoutSeconds = timeout.inSeconds <= 0 ? 1 : timeout.inSeconds;
    final result = await _execute(
      (command) =>
          command.send_object(<Object>['BRPOP', queueKey, '$timeoutSeconds']),
    );
    if (result == null) {
      return null;
    }
    if (result is List && result.length >= 2) {
      final payload = result[1]?.toString().trim() ?? '';
      return payload.isEmpty ? null : payload;
    }
    return null;
  }

  @override
  Future<void> enqueueDelayed(
    String queueKey,
    String payload, {
    required DateTime runAtUtc,
  }) {
    final score = runAtUtc.toUtc().millisecondsSinceEpoch;
    return _executeVoid(
      (command) =>
          command.send_object(<Object>['ZADD', queueKey, '$score', payload]),
    );
  }

  @override
  Future<List<String>> moveDueDelayed({
    required String delayedQueueKey,
    required String queueKey,
    required DateTime nowUtc,
    int limit = 100,
  }) async {
    final safeLimit = limit <= 0
        ? 1
        : limit > 500
        ? 500
        : limit;
    final threshold = nowUtc.toUtc().millisecondsSinceEpoch;
    final dueRaw = await _execute(
      (command) => command.send_object(<Object>[
        'ZRANGEBYSCORE',
        delayedQueueKey,
        '-inf',
        '$threshold',
        'LIMIT',
        '0',
        '$safeLimit',
      ]),
    );
    if (dueRaw is! List || dueRaw.isEmpty) {
      return const <String>[];
    }
    final moved = <String>[];
    for (final candidate in dueRaw) {
      final payload = candidate?.toString() ?? '';
      if (payload.isEmpty) {
        continue;
      }
      final removed = await _execute(
        (command) =>
            command.send_object(<Object>['ZREM', delayedQueueKey, payload]),
      );
      if (_asInt(removed) <= 0) {
        continue;
      }
      await enqueue(queueKey, payload);
      moved.add(payload);
    }
    return moved;
  }

  @override
  Future<void> pushDeadLetter(String queueKey, String payload) {
    return _executeVoid(
      (command) => command.send_object(<Object>['LPUSH', queueKey, payload]),
    );
  }

  @override
  Future<void> set(String key, String value, {Duration? ttl}) {
    final seconds = ttl == null ? 0 : ttl.inSeconds;
    if (seconds <= 0) {
      return _executeVoid(
        (command) => command.send_object(<Object>['SET', key, value]),
      );
    }
    return _executeVoid(
      (command) =>
          command.send_object(<Object>['SET', key, value, 'EX', '$seconds']),
    );
  }

  @override
  Future<String?> get(String key) async {
    final result = await _execute(
      (command) => command.send_object(<Object>['GET', key]),
    );
    final normalized = result?.toString();
    if (normalized == null || normalized.isEmpty) {
      return null;
    }
    return normalized;
  }

  @override
  Future<void> del(String key) {
    return _executeVoid((command) => command.send_object(<Object>['DEL', key]));
  }

  @override
  Future<int> incrementWithWindow(
    String key, {
    required Duration window,
  }) async {
    final seconds = window.inSeconds <= 0 ? 1 : window.inSeconds;
    return _execute((command) async {
      final incremented = await command.send_object(<Object>['INCR', key]);
      final count = _asInt(incremented);
      if (count <= 1) {
        await command.send_object(<Object>['EXPIRE', key, '$seconds']);
      }
      return count;
    });
  }

  Future<void> _authenticateIfNeeded(Uri uri, Command command) async {
    if (uri.userInfo.trim().isEmpty) {
      return;
    }
    final separator = uri.userInfo.indexOf(':');
    final username = separator < 0
        ? ''
        : Uri.decodeComponent(uri.userInfo.substring(0, separator).trim());
    final password = separator < 0
        ? Uri.decodeComponent(uri.userInfo.trim())
        : Uri.decodeComponent(uri.userInfo.substring(separator + 1).trim());
    if (password.isEmpty) {
      return;
    }
    if (username.isEmpty) {
      await command.send_object(<Object>['AUTH', password]);
      return;
    }
    await command.send_object(<Object>['AUTH', username, password]);
  }

  Future<void> _selectDatabaseIfNeeded(Uri uri, Command command) async {
    final dbIndex = _resolveDatabaseIndex(uri);
    if (dbIndex <= 0) {
      return;
    }
    await command.send_object(<Object>['SELECT', '$dbIndex']);
  }

  int _resolveDatabaseIndex(Uri uri) {
    final path = uri.path.trim();
    if (path.isEmpty || path == '/') {
      return 0;
    }
    final segment = path.startsWith('/') ? path.substring(1) : path;
    return int.tryParse(segment) ?? 0;
  }

  Future<T> _execute<T>(Future<T> Function(Command command) action) async {
    Object? lastError;
    final attempts = maxReconnectAttempts < 1 ? 1 : maxReconnectAttempts;
    for (var attempt = 1; attempt <= attempts; attempt++) {
      try {
        await connect();
        final command = _command;
        if (command == null) {
          throw StateError('redis_command_unavailable');
        }
        return await action(command);
      } catch (error) {
        lastError = error;
        await _resetConnection();
        if (attempt < attempts) {
          await Future<void>.delayed(Duration(milliseconds: 50 * attempt));
        }
      }
    }
    throw StateError('redis_command_failed: $lastError');
  }

  Future<void> _executeVoid(
    Future<Object?> Function(Command command) action,
  ) async {
    await _execute<Object?>((command) => action(command));
  }

  Future<void> _resetConnection() async {
    final connection = _connection;
    _command = null;
    _connection = null;
    if (connection != null) {
      try {
        await connection.close();
      } catch (error) {
        _warningSink?.call('WARN: redis connection close failed: $error');
      }
    }
  }

  int _asInt(Object? value) {
    if (value is int) {
      return value;
    }
    if (value is num) {
      return value.toInt();
    }
    if (value is String) {
      return int.tryParse(value.trim()) ?? 0;
    }
    return 0;
  }
}

class InMemoryRedisClient implements RedisQueueClient {
  InMemoryRedisClient({DateTime Function()? nowUtc})
    : _nowUtc = nowUtc ?? (() => DateTime.now().toUtc());

  final DateTime Function() _nowUtc;
  final Map<String, _StringEntry> _strings = <String, _StringEntry>{};
  final Map<String, List<String>> _lists = <String, List<String>>{};
  final Map<String, List<_ScoredPayload>> _sortedSets =
      <String, List<_ScoredPayload>>{};
  bool _closed = false;

  @override
  bool get isConfigured => true;

  @override
  Future<void> close() async {
    _closed = true;
  }

  @override
  Future<void> connect() async {
    if (_closed) {
      throw StateError('in_memory_redis_closed');
    }
  }

  @override
  Future<bool> ping() async => !_closed;

  @override
  Future<void> enqueue(String queueKey, String payload) async {
    final queue = _lists.putIfAbsent(queueKey, () => <String>[]);
    queue.insert(0, payload);
  }

  @override
  Future<String?> dequeue(
    String queueKey, {
    Duration timeout = const Duration(seconds: 1),
  }) async {
    final queue = _lists[queueKey];
    if (queue == null || queue.isEmpty) {
      return null;
    }
    return queue.removeLast();
  }

  @override
  Future<void> enqueueDelayed(
    String queueKey,
    String payload, {
    required DateTime runAtUtc,
  }) async {
    final set = _sortedSets.putIfAbsent(queueKey, () => <_ScoredPayload>[]);
    set.add(
      _ScoredPayload(
        payload: payload,
        score: runAtUtc.toUtc().millisecondsSinceEpoch,
      ),
    );
  }

  @override
  Future<List<String>> moveDueDelayed({
    required String delayedQueueKey,
    required String queueKey,
    required DateTime nowUtc,
    int limit = 100,
  }) async {
    final set = _sortedSets[delayedQueueKey];
    if (set == null || set.isEmpty) {
      return const <String>[];
    }
    final threshold = nowUtc.toUtc().millisecondsSinceEpoch;
    set.sort((left, right) => left.score.compareTo(right.score));
    final moved = <String>[];
    final retained = <_ScoredPayload>[];
    for (final item in set) {
      if (item.score <= threshold && moved.length < limit) {
        moved.add(item.payload);
        continue;
      }
      retained.add(item);
    }
    _sortedSets[delayedQueueKey] = retained;
    for (final payload in moved) {
      await enqueue(queueKey, payload);
    }
    return moved;
  }

  @override
  Future<void> pushDeadLetter(String queueKey, String payload) {
    return enqueue(queueKey, payload);
  }

  @override
  Future<void> set(String key, String value, {Duration? ttl}) async {
    final expiresAt = ttl == null || ttl.inSeconds <= 0
        ? null
        : _nowUtc().add(ttl);
    _strings[key] = _StringEntry(value: value, expiresAt: expiresAt);
  }

  @override
  Future<String?> get(String key) async {
    _evictExpired(key);
    return _strings[key]?.value;
  }

  @override
  Future<void> del(String key) async {
    _strings.remove(key);
  }

  @override
  Future<int> incrementWithWindow(
    String key, {
    required Duration window,
  }) async {
    _evictExpired(key);
    final existing = _strings[key];
    var count = int.tryParse(existing?.value ?? '0') ?? 0;
    count += 1;
    final expiresAt = count == 1 ? _nowUtc().add(window) : existing?.expiresAt;
    _strings[key] = _StringEntry(value: '$count', expiresAt: expiresAt);
    return count;
  }

  void _evictExpired(String key) {
    final entry = _strings[key];
    if (entry == null) {
      return;
    }
    final expiresAt = entry.expiresAt;
    if (expiresAt != null && !expiresAt.isAfter(_nowUtc())) {
      _strings.remove(key);
    }
  }
}

class _StringEntry {
  const _StringEntry({required this.value, required this.expiresAt});

  final String value;
  final DateTime? expiresAt;
}

class _ScoredPayload {
  const _ScoredPayload({required this.payload, required this.score});

  final String payload;
  final int score;
}
