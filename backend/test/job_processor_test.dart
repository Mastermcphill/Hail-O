import 'dart:convert';

import 'package:test/test.dart';
import 'package:uuid/uuid.dart';

import '../infra/redis_client.dart';
import '../jobs/job.dart';
import '../jobs/job_processor.dart';
import '../jobs/job_registry.dart';

void main() {
  group('QueueJobProcessor', () {
    test('enqueue and process succeeds', () async {
      final now = DateTime.utc(2026, 2, 26, 10, 0, 0);
      final redis = InMemoryRedisClient(nowUtc: () => now);
      final registry = QueueJobRegistry();
      var handled = false;
      registry.register(QueueJobTypes.analyticsFlush, (_) async {
        handled = true;
      });
      final processor = QueueJobProcessor(
        redisClient: redis,
        registry: registry,
        nowUtc: () => now,
        uuid: const Uuid(),
      );
      await processor.enqueueJob(QueueJobTypes.analyticsFlush);

      final processed = await processor.processOnce();
      expect(processed, isTrue);
      expect(handled, isTrue);
    });

    test('failed job retries with backoff and later succeeds', () async {
      var now = DateTime.utc(2026, 2, 26, 10, 0, 0);
      final redis = InMemoryRedisClient(nowUtc: () => now);
      final registry = QueueJobRegistry();
      var attempts = 0;
      registry.register(QueueJobTypes.reconcilePayment, (_) async {
        attempts += 1;
        if (attempts == 1) {
          throw StateError('transient');
        }
      });
      final processor = QueueJobProcessor(
        redisClient: redis,
        registry: registry,
        nowUtc: () => now,
      );
      await processor.enqueueJob(
        QueueJobTypes.reconcilePayment,
        maxAttempts: 3,
      );

      expect(await processor.processOnce(), isTrue);
      expect(attempts, 1);
      expect(
        await redis.moveDueDelayed(
          delayedQueueKey: QueueNames.delayed,
          queueKey: QueueNames.jobs,
          nowUtc: now,
        ),
        isEmpty,
      );

      now = now.add(const Duration(seconds: 1));
      expect(await processor.processOnce(), isTrue);
      expect(attempts, 2);
    });

    test('max attempts moves job to dead-letter queue', () async {
      var now = DateTime.utc(2026, 2, 26, 10, 0, 0);
      final redis = InMemoryRedisClient(nowUtc: () => now);
      final registry = QueueJobRegistry();
      registry.register(QueueJobTypes.sendOtp, (_) async {
        throw StateError('always-fail');
      });
      final processor = QueueJobProcessor(
        redisClient: redis,
        registry: registry,
        nowUtc: () => now,
      );
      await processor.enqueueJob(QueueJobTypes.sendOtp, maxAttempts: 2);

      expect(await processor.processOnce(), isTrue);
      now = now.add(const Duration(seconds: 1));
      expect(await processor.processOnce(), isTrue);

      final deadPayload = await redis.dequeue(QueueNames.dead);
      expect(deadPayload, isNotNull);
      final decoded = jsonDecode(deadPayload!) as Map<String, dynamic>;
      expect(decoded['reason'], 'max_attempts_reached');
    });
  });
}
