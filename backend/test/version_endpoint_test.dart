import 'dart:convert';

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

  test('/version returns build metadata', () async {
    final db = await HailODatabase().openInMemory();
    addTearDown(() async => db.close());

    final handler = _buildHandler(
      db: db,
      dbHealthCheck: () async => true,
      buildInfo: const <String, Object?>{
        'version': '1.2.3',
        'commit': 'abc1234',
      },
    );

    final response = await _request(handler, '/version');
    expect(response.statusCode, 200);
    final body = await _decodeBody(response);
    expect(body['ok'], true);
    expect(body['version'], '1.2.3');
    expect(body['commit'], 'abc1234');
  });

  test('/health returns quickly when dependency health check stalls', () async {
    final db = await HailODatabase().openInMemory();
    addTearDown(() async => db.close());

    final handler = _buildHandler(
      db: db,
      dbHealthCheck: () async {
        await Future<void>.delayed(const Duration(seconds: 5));
        return true;
      },
      buildInfo: const <String, Object?>{'commit': 'slow-health-test'},
    );

    final stopwatch = Stopwatch()..start();
    final response = await _request(handler, '/health');
    stopwatch.stop();

    expect(response.statusCode, 503);
    expect(stopwatch.elapsedMilliseconds, lessThan(1200));
    final body = await _decodeBody(response);
    expect(body['ok'], false);
    expect(body['db_ok'], false);
  });

  test('/health defaults to slim payload even in non-production', () async {
    final db = await HailODatabase().openInMemory();
    addTearDown(() async => db.close());

    final handler = _buildHandler(
      db: db,
      dbHealthCheck: () async => true,
      buildInfo: <String, Object?>{
        'commit': 'abc1234',
        'runtime': 'dart_vm',
        'debug_blob': 'x' * 8000,
      },
      environmentMap: const <String, String>{'ENV': 'staging'},
    );

    final response = await _request(handler, '/health');
    expect(response.statusCode, 200);
    final body = await _decodeBody(response);
    expect(body['ok'], true);
    expect(body['env'], 'staging');
    final build = Map<String, Object?>.from(body['build'] as Map);
    expect(build['commit'], 'abc1234');
    expect(build['runtime'], 'dart_vm');
    expect(build.containsKey('debug_blob'), isFalse);
  });

  test('/health verbose returns full payload outside production', () async {
    final db = await HailODatabase().openInMemory();
    addTearDown(() async => db.close());

    final handler = _buildHandler(
      db: db,
      dbHealthCheck: () async => true,
      buildInfo: <String, Object?>{
        'commit': 'abc1234',
        'runtime': 'dart_vm',
        'debug_blob': 'x' * 8000,
      },
      environmentMap: const <String, String>{'ENV': 'staging'},
    );

    final response = await _request(handler, '/health?verbose=1');
    expect(response.statusCode, 200);
    final body = await _decodeBody(response);
    expect(body['env'], 'staging');
    final build = Map<String, Object?>.from(body['build'] as Map);
    expect(build['commit'], 'abc1234');
    expect(build['runtime'], 'dart_vm');
    expect(build.containsKey('debug_blob'), isTrue);
  });

  test('/health verbose is ignored in production and remains slim', () async {
    final db = await HailODatabase().openInMemory();
    addTearDown(() async => db.close());

    final handler = _buildHandler(
      db: db,
      dbHealthCheck: () async => true,
      buildInfo: <String, Object?>{
        'commit': 'abc1234',
        'runtime': 'dart_vm',
        'debug_blob': 'x' * 8000,
      },
      environmentMap: const <String, String>{'ENV': 'production'},
    );

    final response = await _request(handler, '/health?verbose=true');
    expect(response.statusCode, 200);
    final body = await _decodeBody(response);
    expect(body['env'], 'production');
    final build = Map<String, Object?>.from(body['build'] as Map);
    expect(build['commit'], 'abc1234');
    expect(build['runtime'], 'dart_vm');
    expect(build.containsKey('debug_blob'), isFalse);
  });

  test('/health supports HEAD requests', () async {
    final db = await HailODatabase().openInMemory();
    addTearDown(() async => db.close());

    final handler = _buildHandler(
      db: db,
      dbHealthCheck: () async => true,
      buildInfo: const <String, Object?>{'commit': 'abc1234'},
      environmentMap: const <String, String>{'ENV': 'production'},
    );

    final response = await _request(handler, '/health', method: 'HEAD');
    expect(response.statusCode, 200);
  });

  test('/ready returns 200 when db is healthy and migrations match', () async {
    final db = await HailODatabase().openInMemory();
    addTearDown(() async => db.close());
    await db.execute('DROP TABLE IF EXISTS schema_migrations');
    await db.execute(
      'CREATE TABLE schema_migrations(version INTEGER NOT NULL)',
    );
    await db.insert('schema_migrations', <String, Object?>{'version': 25});

    final handler = _buildHandler(
      db: db,
      dbHealthCheck: () async => true,
      buildInfo: const <String, Object?>{
        'commit': 'ready-test',
        'migration_head': 25,
      },
    );

    final response = await _request(handler, '/ready');
    expect(response.statusCode, 200);
    final body = await _decodeBody(response);
    expect(body['ok'], isTrue);
    expect(body['ready'], isTrue);
    expect(body['db_ok'], isTrue);
    expect(body['migrations_ok'], isTrue);
    expect(body['expected_migration_head'], 25);
    expect(body['applied_migration_head'], 25);
  });

  test('/ready returns 503 when migration head mismatches', () async {
    final db = await HailODatabase().openInMemory();
    addTearDown(() async => db.close());
    await db.execute('DROP TABLE IF EXISTS schema_migrations');
    await db.execute(
      'CREATE TABLE schema_migrations(version INTEGER NOT NULL)',
    );
    await db.insert('schema_migrations', <String, Object?>{'version': 24});

    final handler = _buildHandler(
      db: db,
      dbHealthCheck: () async => true,
      buildInfo: const <String, Object?>{
        'commit': 'ready-test',
        'migration_head': 25,
      },
    );

    final response = await _request(handler, '/ready');
    expect(response.statusCode, 503);
    final body = await _decodeBody(response);
    expect(body['ok'], isFalse);
    expect(body['ready'], isFalse);
    expect(body['db_ok'], isTrue);
    expect(body['migrations_ok'], isFalse);
    expect(body['expected_migration_head'], 25);
    expect(body['applied_migration_head'], 24);
  });

  test('/api/ready mirrors readiness result', () async {
    final db = await HailODatabase().openInMemory();
    addTearDown(() async => db.close());

    final handler = _buildHandler(
      db: db,
      dbHealthCheck: () async => false,
      buildInfo: const <String, Object?>{
        'commit': 'ready-test',
        'migration_head': 25,
      },
    );

    final response = await _request(handler, '/api/ready');
    expect(response.statusCode, 503);
    final body = await _decodeBody(response);
    expect(body['ok'], isFalse);
    expect(body['ready'], isFalse);
    expect(body['db_ok'], isFalse);
  });
}

Handler _buildHandler({
  required Database db,
  required Future<bool> Function() dbHealthCheck,
  required Map<String, Object?> buildInfo,
  Map<String, String> environmentMap = const <String, String>{},
}) {
  return AppServer(
    db: db,
    tokenService: TokenService(secret: 'backend-test-secret'),
    dbMode: 'sqlite',
    environment: 'test',
    requestMetrics: RequestMetrics(),
    dbHealthCheck: dbHealthCheck,
    buildInfo: buildInfo,
    authCredentialsStore: SqliteAuthCredentialsStore(db),
    rideRequestMetadataStore: SqliteRideRequestMetadataStore(db),
    operationalRecordStore: const SqliteOperationalRecordStore(),
    environmentMap: environmentMap,
  ).buildHandler();
}

Future<Response> _request(
  Handler handler,
  String path, {
  String method = 'GET',
}) async {
  return handler(
    shelf.Request(
      method,
      Uri.parse('http://localhost$path'),
      headers: const <String, String>{'accept': 'application/json'},
    ),
  );
}

Future<Map<String, Object?>> _decodeBody(Response response) async {
  final decoded = jsonDecode(await response.readAsString());
  return Map<String, Object?>.from(decoded as Map<String, dynamic>);
}
