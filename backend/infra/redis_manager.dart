import 'redis_client.dart';

typedef RedisClientFactory =
    RedisQueueClient Function(
      String redisUrl, {
      void Function(String line)? warningSink,
    });

class RedisManager {
  const RedisManager._({
    required this.enabled,
    required this.configured,
    required this.client,
  });

  final bool enabled;
  final bool configured;
  final RedisQueueClient? client;

  static Future<RedisManager> fromEnvironment(
    Map<String, String> env, {
    void Function(String line)? warningSink,
    RedisClientFactory? clientFactory,
  }) async {
    final redisEnabled = _parseBool(env['REDIS_ENABLED']);
    final redisUrl = (env['REDIS_URL'] ?? '').trim();
    final redisConfigured = redisUrl.isNotEmpty;
    final buildClient = clientFactory ?? RedisClient.new;

    if (!redisEnabled) {
      return RedisManager._(enabled: false, configured: false, client: null);
    }

    if (!redisConfigured) {
      throw StateError('REDIS_ENABLED=true requires REDIS_URL');
    }

    final redis = buildClient(redisUrl, warningSink: warningSink);
    try {
      await redis.connect();
      return RedisManager._(enabled: true, configured: true, client: redis);
    } catch (error) {
      warningSink?.call(
        'WARN: Redis initialization failed; falling back to in-memory features where possible. error=$error',
      );
      await redis.close();
      return RedisManager._(enabled: true, configured: true, client: null);
    }
  }

  Future<void> close() async {
    await client?.close();
  }
}

bool _parseBool(String? value) {
  final normalized = value?.trim().toLowerCase() ?? '';
  return normalized == '1' ||
      normalized == 'true' ||
      normalized == 'yes' ||
      normalized == 'y' ||
      normalized == 'on';
}
