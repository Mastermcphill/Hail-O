import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:shelf/shelf.dart';
import 'package:shelf/shelf.dart' as shelf;
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:test/test.dart';

import '../../lib/data/sqlite/hailo_database.dart';
import '../infra/request_metrics.dart';
import '../infra/token_service.dart';
import '../modules/auth/sqlite_auth_credentials_store.dart';
import '../modules/rides/sqlite_operational_record_store.dart';
import '../modules/rides/sqlite_ride_request_metadata_store.dart';
import '../server/app_server.dart';

void main() {
  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  test('OTP request creates challenge and does not expose code', () async {
    final db = await HailODatabase().openInMemory();
    addTearDown(() => db.close());
    final handler = _buildHandler(db);

    const phone = '+15551234567';
    final response = await _postJson(
      handler,
      '/auth/otp/request',
      body: const <String, Object?>{'phone_e164': phone},
    );
    expect(response.statusCode, 200);
    final payload = await _decodeBody(response);
    expect(payload, const <String, Object?>{'ok': true});
    expect(payload.containsKey('code'), isFalse);

    final rows = await db.query(
      'otp_challenges',
      where: 'phone_e164 = ?',
      whereArgs: const <Object>[phone],
      limit: 1,
    );
    expect(rows.length, 1);
    final challenge = rows.first;
    final codeHash = (challenge['code_hash'] as String?) ?? '';
    expect(codeHash.isNotEmpty, isTrue);
    expect(codeHash, isNot('123456'));
    expect((challenge['attempts'] as num?)?.toInt(), 0);
  });

  test('OTP verify success returns access and refresh tokens', () async {
    final db = await HailODatabase().openInMemory();
    addTearDown(() => db.close());
    final handler = _buildHandler(db);

    const phone = '+15551230001';
    await _postJson(
      handler,
      '/auth/otp/request',
      body: const <String, Object?>{'phone_e164': phone},
    );
    final verify = await _postJson(
      handler,
      '/auth/otp/verify',
      body: const <String, Object?>{'phone_e164': phone, 'code': '123456'},
    );
    expect(verify.statusCode, 200);
    final body = await _decodeBody(verify);
    expect((body['access_token'] as String?)?.isNotEmpty, isTrue);
    expect((body['refresh_token'] as String?)?.isNotEmpty, isTrue);
    final user = Map<String, Object?>.from(body['user'] as Map);
    expect(user['phone_e164'], phone);
    expect((user['id'] as String?)?.isNotEmpty, isTrue);
  });

  test(
    'OTP verify wrong code increments attempts and eventually locks',
    () async {
      final db = await HailODatabase().openInMemory();
      addTearDown(() => db.close());
      final handler = _buildHandler(
        db,
        environmentMap: const <String, String>{
          'ENV': 'test',
          'OTP_DEV_BYPASS': 'true',
          'OTP_DEV_BYPASS_CODE': '123456',
          'OTP_MAX_ATTEMPTS': '3',
          'OTP_LOCKOUT_SECONDS': '600',
        },
      );

      const phone = '+15551230002';
      await _postJson(
        handler,
        '/auth/otp/request',
        body: const <String, Object?>{'phone_e164': phone},
      );

      final first = await _postJson(
        handler,
        '/auth/otp/verify',
        body: const <String, Object?>{'phone_e164': phone, 'code': '000000'},
      );
      expect(first.statusCode, 401);

      final second = await _postJson(
        handler,
        '/auth/otp/verify',
        body: const <String, Object?>{'phone_e164': phone, 'code': '000000'},
      );
      expect(second.statusCode, 401);

      final third = await _postJson(
        handler,
        '/auth/otp/verify',
        body: const <String, Object?>{'phone_e164': phone, 'code': '000000'},
      );
      expect(third.statusCode, 423);
      final thirdBody = await _decodeBody(third);
      expect(thirdBody['error_code'], 'OTP_LOCKED');

      final rows = await db.query(
        'otp_challenges',
        where: 'phone_e164 = ?',
        whereArgs: const <Object>[phone],
        orderBy: 'created_at DESC',
        limit: 1,
      );
      expect(rows.length, 1);
      final challenge = rows.first;
      expect((challenge['attempts'] as num?)?.toInt(), 3);
      expect((challenge['locked_until'] as String?)?.isNotEmpty, isTrue);
    },
  );

  test('refresh works and revoked token fails', () async {
    final db = await HailODatabase().openInMemory();
    addTearDown(() => db.close());
    final handler = _buildHandler(db);

    const phone = '+15551230003';
    await _postJson(
      handler,
      '/auth/otp/request',
      body: const <String, Object?>{'phone_e164': phone},
    );
    final verify = await _postJson(
      handler,
      '/auth/otp/verify',
      body: const <String, Object?>{'phone_e164': phone, 'code': '123456'},
    );
    final verifyBody = await _decodeBody(verify);
    final refreshToken = (verifyBody['refresh_token'] as String?) ?? '';
    expect(refreshToken.isNotEmpty, isTrue);

    final refresh = await _postJson(
      handler,
      '/auth/token/refresh',
      body: <String, Object?>{'refresh_token': refreshToken},
    );
    expect(refresh.statusCode, 200);
    final refreshBody = await _decodeBody(refresh);
    expect((refreshBody['access_token'] as String?)?.isNotEmpty, isTrue);

    final tokenHash = sha256.convert(utf8.encode(refreshToken)).toString();
    await db.update(
      'refresh_tokens',
      <String, Object?>{'revoked_at': DateTime.now().toUtc().toIso8601String()},
      where: 'token_hash = ?',
      whereArgs: <Object>[tokenHash],
    );

    final revokedRefresh = await _postJson(
      handler,
      '/auth/token/refresh',
      body: <String, Object?>{'refresh_token': refreshToken},
    );
    expect(revokedRefresh.statusCode, 401);
    final revokedBody = await _decodeBody(revokedRefresh);
    expect(revokedBody['error_code'], 'INVALID_REFRESH_TOKEN');
  });
}

Handler _buildHandler(
  Database db, {
  Map<String, String> environmentMap = const <String, String>{
    'ENV': 'test',
    'OTP_DEV_BYPASS': 'true',
    'OTP_DEV_BYPASS_CODE': '123456',
  },
}) {
  return AppServer(
    db: db,
    tokenService: TokenService(secret: 'backend-test-secret'),
    dbMode: 'sqlite',
    environment: (environmentMap['ENV'] ?? 'test'),
    requestMetrics: RequestMetrics(),
    dbHealthCheck: () async => true,
    buildInfo: const <String, Object?>{'commit': 'test', 'runtime': 'test'},
    authCredentialsStore: SqliteAuthCredentialsStore(db),
    rideRequestMetadataStore: SqliteRideRequestMetadataStore(db),
    operationalRecordStore: const SqliteOperationalRecordStore(),
    environmentMap: environmentMap,
  ).buildHandler();
}

Future<Response> _postJson(
  Handler handler,
  String path, {
  required Map<String, Object?> body,
}) async {
  final request = shelf.Request(
    'POST',
    Uri.parse('http://localhost$path'),
    headers: const <String, String>{'content-type': 'application/json'},
    body: jsonEncode(body),
  );
  return handler(request);
}

Future<Map<String, Object?>> _decodeBody(Response response) async {
  final decoded = jsonDecode(await response.readAsString());
  return Map<String, Object?>.from(decoded as Map<String, dynamic>);
}
