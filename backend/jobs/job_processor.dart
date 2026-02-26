import 'dart:async';
import 'dart:convert';

import 'package:uuid/uuid.dart';

import '../infra/redis_client.dart';
import 'job.dart';
import 'job_registry.dart';

class QueueJobProcessor {
  QueueJobProcessor({
    required RedisQueueClient redisClient,
    required QueueJobRegistry registry,
    this.queueKey = QueueNames.jobs,
    this.delayedQueueKey = QueueNames.delayed,
    this.deadQueueKey = QueueNames.dead,
    this.dequeueTimeout = const Duration(seconds: 1),
    this.maxDelayBatch = 50,
    this.maxBackoff = const Duration(minutes: 15),
    DateTime Function()? nowUtc,
    Uuid? uuid,
    void Function(String line)? warningSink,
  }) : _redisClient = redisClient,
       _registry = registry,
       _nowUtc = nowUtc ?? (() => DateTime.now().toUtc()),
       _uuid = uuid ?? const Uuid(),
       _warningSink = warningSink;

  final RedisQueueClient _redisClient;
  final QueueJobRegistry _registry;
  final String queueKey;
  final String delayedQueueKey;
  final String deadQueueKey;
  final Duration dequeueTimeout;
  final int maxDelayBatch;
  final Duration maxBackoff;
  final DateTime Function() _nowUtc;
  final Uuid _uuid;
  final void Function(String line)? _warningSink;

  bool _stopped = false;

  Future<void> enqueueJob(
    String type, {
    Map<String, Object?> payload = const <String, Object?>{},
    int maxAttempts = 5,
    DateTime? runAtUtc,
  }) {
    final runAt = (runAtUtc ?? _nowUtc()).toUtc();
    final job = QueueJob(
      id: _uuid.v4(),
      type: type.trim(),
      payload: payload,
      attempts: 0,
      maxAttempts: maxAttempts <= 0 ? 1 : maxAttempts,
      runAtTimestamp: runAt.millisecondsSinceEpoch,
    );
    return enqueue(job);
  }

  Future<void> enqueue(QueueJob job) async {
    final now = _nowUtc().millisecondsSinceEpoch;
    final encoded = job.toJsonString();
    if (job.runAtTimestamp > now) {
      await _redisClient.enqueueDelayed(
        delayedQueueKey,
        encoded,
        runAtUtc: DateTime.fromMillisecondsSinceEpoch(
          job.runAtTimestamp,
          isUtc: true,
        ),
      );
      return;
    }
    await _redisClient.enqueue(queueKey, encoded);
  }

  Future<void> run() async {
    _stopped = false;
    while (!_stopped) {
      try {
        await processOnce();
      } catch (error) {
        _warningSink?.call('WARN: queue processor cycle failed: $error');
        await Future<void>.delayed(const Duration(milliseconds: 250));
      }
    }
  }

  Future<bool> processOnce() async {
    await _redisClient.moveDueDelayed(
      delayedQueueKey: delayedQueueKey,
      queueKey: queueKey,
      nowUtc: _nowUtc(),
      limit: maxDelayBatch,
    );
    final encoded = await _redisClient.dequeue(
      queueKey,
      timeout: dequeueTimeout,
    );
    if (encoded == null || encoded.trim().isEmpty) {
      return false;
    }
    QueueJob job;
    try {
      job = QueueJob.fromJsonString(encoded);
    } on FormatException catch (error) {
      await _deadLetterRaw(
        encoded,
        error: error.message,
        reason: 'invalid_job_payload',
      );
      return true;
    }
    final handler = _registry.lookup(job.type);
    if (handler == null) {
      await _deadLetter(
        job,
        error: 'No registered handler for ${job.type}',
        reason: 'unknown_job_type',
      );
      return true;
    }
    try {
      await handler(job);
      return true;
    } catch (error) {
      final nextAttempts = job.attempts + 1;
      if (nextAttempts >= job.maxAttempts) {
        await _deadLetter(
          job.copyWith(attempts: nextAttempts),
          error: error.toString(),
          reason: 'max_attempts_reached',
        );
        return true;
      }
      final delay = _retryDelay(nextAttempts);
      final retryJob = job.copyWith(
        attempts: nextAttempts,
        runAtTimestamp: _nowUtc().add(delay).millisecondsSinceEpoch,
      );
      await enqueue(retryJob);
      return true;
    }
  }

  void stop() {
    _stopped = true;
  }

  Duration _retryDelay(int attempts) {
    var seconds = 1;
    for (var index = 1; index < attempts; index++) {
      seconds *= 2;
      if (seconds >= maxBackoff.inSeconds) {
        seconds = maxBackoff.inSeconds;
        break;
      }
    }
    if (seconds <= 0) {
      seconds = 1;
    }
    return Duration(seconds: seconds);
  }

  Future<void> _deadLetter(
    QueueJob job, {
    required String error,
    required String reason,
  }) {
    final payload = jsonEncode(<String, Object?>{
      'job': job.toJson(),
      'error': _truncateError(error),
      'reason': reason,
      'failed_at': _nowUtc().toIso8601String(),
    });
    return _redisClient.pushDeadLetter(deadQueueKey, payload);
  }

  Future<void> _deadLetterRaw(
    String rawPayload, {
    required String error,
    required String reason,
  }) {
    final payload = jsonEncode(<String, Object?>{
      'raw_payload': rawPayload,
      'error': _truncateError(error),
      'reason': reason,
      'failed_at': _nowUtc().toIso8601String(),
    });
    return _redisClient.pushDeadLetter(deadQueueKey, payload);
  }

  String _truncateError(String value) {
    final normalized = value.trim();
    if (normalized.length <= 512) {
      return normalized;
    }
    return normalized.substring(0, 512);
  }
}

