import 'package:test/test.dart';

import '../infra/redis_client.dart';
import '../infra/redis_manager.dart';

class _FakeRedisClient extends InMemoryRedisClient {
  _FakeRedisClient({this.failOnConnect = false});

  final bool failOnConnect;
  int connectCalls = 0;

  @override
  Future<void> connect() async {
    connectCalls += 1;
    if (failOnConnect) {
      throw StateError('simulated_connect_failure');
    }
    return super.connect();
  }
}

void main() {
  test('defaults to bypass mode when REDIS_ENABLED is unset', () async {
    var factoryCalled = false;
    final manager = await RedisManager.fromEnvironment(
      const <String, String>{},
      clientFactory: (String _, {void Function(String line)? warningSink}) {
        factoryCalled = true;
        return _FakeRedisClient();
      },
    );

    expect(manager.enabled, isFalse);
    expect(manager.configured, isFalse);
    expect(manager.client, isNull);
    expect(factoryCalled, isFalse);
  });

  test('bypasses Redis when REDIS_ENABLED=false', () async {
    var factoryCalled = false;
    final manager = await RedisManager.fromEnvironment(
      const <String, String>{
        'REDIS_ENABLED': 'false',
        'REDIS_URL': 'redis://127.0.0.1:6379/0',
      },
      clientFactory: (String _, {void Function(String line)? warningSink}) {
        factoryCalled = true;
        return _FakeRedisClient();
      },
    );

    expect(manager.enabled, isFalse);
    expect(manager.configured, isFalse);
    expect(manager.client, isNull);
    expect(factoryCalled, isFalse);
  });

  test('fails fast when REDIS_ENABLED=true and REDIS_URL is missing', () async {
    expect(
      () => RedisManager.fromEnvironment(const <String, String>{
        'REDIS_ENABLED': 'true',
      }),
      throwsA(
        isA<StateError>().having(
          (StateError error) => error.message,
          'message',
          contains('REDIS_ENABLED=true requires REDIS_URL'),
        ),
      ),
    );
  });

  test(
    'connects when REDIS_ENABLED=true and REDIS_URL is configured',
    () async {
      final fakeClient = _FakeRedisClient();
      final manager = await RedisManager.fromEnvironment(
        const <String, String>{
          'REDIS_ENABLED': 'true',
          'REDIS_URL': 'redis://127.0.0.1:6379/0',
        },
        clientFactory:
            (String redisUrl, {void Function(String line)? warningSink}) {
              expect(redisUrl, 'redis://127.0.0.1:6379/0');
              return fakeClient;
            },
      );

      expect(fakeClient.connectCalls, 1);
      expect(manager.enabled, isTrue);
      expect(manager.configured, isTrue);
      expect(manager.client, same(fakeClient));
    },
  );

  test('keeps app bootable when configured redis connection fails', () async {
    final warnings = <String>[];
    final fakeClient = _FakeRedisClient(failOnConnect: true);
    final manager = await RedisManager.fromEnvironment(
      const <String, String>{
        'REDIS_ENABLED': 'true',
        'REDIS_URL': 'redis://127.0.0.1:6379/0',
      },
      warningSink: warnings.add,
      clientFactory: (String _, {void Function(String line)? warningSink}) =>
          fakeClient,
    );

    expect(fakeClient.connectCalls, 1);
    expect(manager.enabled, isTrue);
    expect(manager.configured, isTrue);
    expect(manager.client, isNull);
    expect(
      warnings.any((line) => line.contains('Redis initialization failed')),
      isTrue,
    );
  });
}
