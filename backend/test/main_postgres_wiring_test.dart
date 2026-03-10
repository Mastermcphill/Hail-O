import 'package:shelf/shelf.dart';
import 'package:sqflite_common/sqlite_api.dart';
import 'package:test/test.dart';

import '../infra/db_provider.dart';
import '../infra/postgres_provider.dart';
import '../infra/request_metrics.dart';
import '../infra/runtime_config.dart';
import '../infra/token_service.dart';
import '../main.dart' as backend_main;
import '../server/app_server.dart';

void main() {
  test('postgres runtime defaults to a single connection pool', () async {
    var capturedPoolSize = 0;
    var postgresCloseCalls = 0;
    final fakePostgresProvider = _TrackingPostgresProvider(
      onClose: () => postgresCloseCalls += 1,
    );
    final dbProvider = DbProvider.forTesting(
      sqliteOpener: (_) async => _TrackingSqliteDatabase(onClose: () {}),
      postgresProviderFactory:
          (
            _databaseUrl, {
            poolSize = 4,
            dbSchema = 'public',
            statementTimeoutMs = 10000,
          }) {
            capturedPoolSize = poolSize;
            return fakePostgresProvider;
          },
    );
    final env = const <String, String>{
      'BACKEND_DB_MODE': 'postgres',
      'DATABASE_URL': 'postgres://hailo:secret@localhost:5432/hailo',
    };
    final config = BackendRuntimeConfig.fromEnvironmentMap(env);

    final runtime = await backend_main.openBackendDatabaseRuntime(
      config: config,
      env: env,
      dbProvider: dbProvider,
    );

    expect(runtime.usePostgres, isTrue);
    expect(runtime.dbPoolSize, 1);
    expect(capturedPoolSize, 1);

    await dbProvider.close();
    expect(postgresCloseCalls, 1);
  });

  test(
    'postgres main wiring skips sqlite construction and sqlite close',
    () async {
      var sqliteOpenCalls = 0;
      var sqliteCloseCalls = 0;
      var postgresCloseCalls = 0;
      final fakePostgresProvider = _TrackingPostgresProvider(
        onClose: () => postgresCloseCalls += 1,
      );
      final dbProvider = DbProvider.forTesting(
        sqliteOpener: (_) async {
          sqliteOpenCalls += 1;
          return _TrackingSqliteDatabase(onClose: () => sqliteCloseCalls += 1);
        },
        postgresProviderFactory:
            (
              _databaseUrl, {
              poolSize = 4,
              dbSchema = 'public',
              statementTimeoutMs = 10000,
            }) {
              return fakePostgresProvider;
            },
      );
      final config =
          BackendRuntimeConfig.fromEnvironmentMap(const <String, String>{
            'BACKEND_DB_MODE': 'postgres',
            'DATABASE_URL': 'postgres://hailo:secret@localhost:5432/hailo',
          });

      final runtime = await backend_main.openBackendDatabaseRuntime(
        config: config,
        env: const <String, String>{
          'BACKEND_DB_MODE': 'postgres',
          'DATABASE_URL': 'postgres://hailo:secret@localhost:5432/hailo',
        },
        dbProvider: dbProvider,
      );
      expect(runtime.usePostgres, isTrue);
      expect(runtime.sqliteDb, isNull);
      expect(runtime.postgresProvider, same(fakePostgresProvider));
      expect(sqliteOpenCalls, 0);

      final handler = AppServer(
        db: runtime.sqliteDb,
        tokenService: TokenService(secret: 'backend-test-secret'),
        dbMode: 'postgres',
        environment: 'test',
        requestMetrics: RequestMetrics(),
        dbHealthCheck: () async => true,
        buildInfo: const <String, Object?>{'commit': 'test', 'runtime': 'test'},
        runtimeConfigSnapshot: const <String, Object?>{
          'environment': 'test',
          'db_mode': 'postgres',
          'db_schema': 'public',
        },
        postgresProvider: runtime.postgresProvider,
      ).buildHandler();
      final response = await handler(
        Request('GET', Uri.parse('http://localhost/api/healthz')),
      );
      expect(response.statusCode, 200);

      await dbProvider.close();
      expect(sqliteCloseCalls, 0);
      expect(postgresCloseCalls, 1);
    },
  );
}

class _TrackingSqliteDatabase implements Database {
  _TrackingSqliteDatabase({required this.onClose});

  final void Function() onClose;

  @override
  Future<void> close() async {
    onClose();
  }

  @override
  dynamic noSuchMethod(Invocation invocation) {
    throw UnsupportedError(
      'Unexpected sqlite call in postgres wiring test: ${invocation.memberName}',
    );
  }
}

class _TrackingPostgresProvider extends PostgresProvider {
  _TrackingPostgresProvider({required this.onClose})
    : super('postgres://hailo:secret@localhost:5432/hailo');

  final void Function() onClose;

  @override
  Future<void> close() async {
    onClose();
  }
}
