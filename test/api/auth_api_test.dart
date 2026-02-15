import 'package:flutter_test/flutter_test.dart';

import 'api_test_harness.dart';

void main() {
  test('register then login returns token', () async {
    final harness = await ApiTestHarness.create();
    addTearDown(harness.close);

    final register = await harness.postJson(
      '/auth/register',
      body: <String, Object?>{
        'email': 'rider.auth@example.com',
        'password': 'SuperSecret123',
        'role': 'rider',
      },
      idempotencyKey: 'auth-register-rider-1',
    );
    expect(register.statusCode, 201);
    final registerBody = register.requireJsonMap();
    expect(registerBody['ok'], true);
    expect(registerBody['user_id'], isNotNull);

    final login = await harness.postJson(
      '/auth/login',
      body: <String, Object?>{
        'email': 'rider.auth@example.com',
        'password': 'SuperSecret123',
      },
    );
    expect(login.statusCode, 200);
    final loginBody = login.requireJsonMap();
    expect((loginBody['token'] as String?)?.isNotEmpty, true);
  });

  test('register is idempotent on replay key', () async {
    final harness = await ApiTestHarness.create();
    addTearDown(harness.close);

    const key = 'auth-register-idempotent-1';
    final first = await harness.postJson(
      '/auth/register',
      body: <String, Object?>{
        'email': 'idempotent.auth@example.com',
        'password': 'SuperSecret123',
        'role': 'rider',
      },
      idempotencyKey: key,
    );
    expect(first.statusCode, 201);

    final replay = await harness.postJson(
      '/auth/register',
      body: <String, Object?>{
        'email': 'idempotent.auth@example.com',
        'password': 'SuperSecret123',
        'role': 'rider',
      },
      idempotencyKey: key,
    );
    expect(replay.statusCode, 201);
    final replayBody = replay.requireJsonMap();
    expect(replayBody['replayed'], true);
  });
}
