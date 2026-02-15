import 'dart:io';

import 'package:shelf/shelf_io.dart' as io;

import 'infra/db_provider.dart';
import 'infra/migrator.dart';
import 'infra/postgres_provider.dart';
import 'infra/request_metrics.dart';
import 'infra/runtime_config.dart';
import 'infra/token_service.dart';
import 'modules/auth/auth_credentials_store.dart';
import 'modules/auth/postgres_auth_credentials_store.dart';
import 'modules/auth/sqlite_auth_credentials_store.dart';
import 'modules/rides/postgres_operational_record_store.dart';
import 'modules/rides/postgres_ride_request_metadata_store.dart';
import 'modules/rides/ride_request_metadata_store.dart';
import 'modules/rides/sqlite_operational_record_store.dart';
import 'modules/rides/sqlite_ride_request_metadata_store.dart';
import 'server/middleware/cors_policy_middleware.dart';
import 'server/app_server.dart';

Future<void> main() async {
  final env = Platform.environment;
  final config = BackendRuntimeConfig.fromEnvironment();
  final db = await DbProvider.instance.open(databasePath: config.sqlitePath);
  final requestMetrics = RequestMetrics();
  final environment = (env['ENV'] ?? 'development').trim();
  final dbQueryTimeoutMs =
      int.tryParse((env['DB_QUERY_TIMEOUT_MS'] ?? '10000').trim()) ?? 10000;
  final requestIdleTimeoutSeconds =
      int.tryParse((env['REQUEST_IDLE_TIMEOUT_SECONDS'] ?? '30').trim()) ?? 30;
  final rateLimitEnabled =
      (env['RATE_LIMIT_ENABLED'] ?? 'true').trim().toLowerCase() != 'false';
  final rateLimitWindowSeconds =
      int.tryParse((env['RATE_LIMIT_WINDOW_SECONDS'] ?? '60').trim()) ?? 60;
  final rateLimitMaxRequestsPerIp =
      int.tryParse((env['RATE_LIMIT_MAX_REQUESTS_PER_IP'] ?? '60').trim()) ??
      60;
  final rateLimitMaxRequestsPerUser =
      int.tryParse((env['RATE_LIMIT_MAX_REQUESTS_PER_USER'] ?? '120').trim()) ??
      120;
  final metricsPublic =
      (env['METRICS_PUBLIC'] ?? 'false').trim().toLowerCase() == 'true';
  final migrationHeadVersion = BackendPostgresMigrator.migrationHeadVersion();
  PostgresProvider? postgresProvider;
  AuthCredentialsStore authCredentialsStore = SqliteAuthCredentialsStore(db);
  RideRequestMetadataStore rideRequestMetadataStore =
      SqliteRideRequestMetadataStore(db);
  OperationalRecordStore operationalRecordStore =
      const SqliteOperationalRecordStore();

  if (config.usePostgres) {
    final databaseUrl = config.databaseUrl;
    if (databaseUrl == null || databaseUrl.isEmpty) {
      throw StateError(
        'BACKEND_DB_MODE=postgres requires DATABASE_URL environment variable',
      );
    }
    postgresProvider = PostgresProvider(
      databaseUrl,
      dbSchema: config.dbSchema,
      statementTimeoutMs: dbQueryTimeoutMs,
    );
    await BackendPostgresMigrator(
      postgresProvider: postgresProvider,
      dbSchema: config.dbSchema,
    ).runPendingMigrations();
    authCredentialsStore = PostgresAuthCredentialsStore(postgresProvider);
    rideRequestMetadataStore = PostgresRideRequestMetadataStore(
      postgresProvider,
    );
    operationalRecordStore = PostgresOperationalRecordStore(postgresProvider);
  }

  Future<bool> dbHealthCheck() async {
    try {
      if (config.usePostgres) {
        final rows = await postgresProvider!.withConnection(
          (connection) => connection.query('SELECT 1'),
        );
        return rows.isNotEmpty;
      }
      final rows = await db.rawQuery('SELECT 1');
      return rows.isNotEmpty;
    } catch (_) {
      return false;
    }
  }

  final tokenService = TokenService.fromEnvironment();
  final allowedOrigins = parseAllowedOrigins(env['ALLOWED_ORIGINS']);
  final buildInfo = <String, Object?>{
    'commit': env['RENDER_GIT_COMMIT'] ?? 'local',
    'runtime': 'dart_vm',
    'db_schema': config.dbSchema,
    'migration_head': migrationHeadVersion,
  };
  final runtimeConfigSnapshot = <String, Object?>{
    'environment': environment,
    'db_mode': config.dbMode.name,
    'db_schema': config.dbSchema,
    'cors_enabled': allowedOrigins.isNotEmpty,
    'allowed_origins_count': allowedOrigins.length,
    'rate_limit_enabled': rateLimitEnabled,
    'rate_limit_window_seconds': rateLimitWindowSeconds,
    'rate_limit_max_requests_per_ip': rateLimitMaxRequestsPerIp,
    'rate_limit_max_requests_per_user': rateLimitMaxRequestsPerUser,
    'metrics_public': metricsPublic,
    'metrics_protected': !metricsPublic,
    'db_query_timeout_ms': dbQueryTimeoutMs,
    'request_idle_timeout_seconds': requestIdleTimeoutSeconds,
  };
  final handler = AppServer(
    db: db,
    tokenService: tokenService,
    dbMode: config.dbMode.name,
    environment: environment,
    requestMetrics: requestMetrics,
    metricsPublic: metricsPublic,
    allowedOrigins: allowedOrigins,
    dbHealthCheck: dbHealthCheck,
    buildInfo: buildInfo,
    rateLimitEnabled: rateLimitEnabled,
    rateLimitWindow: Duration(seconds: rateLimitWindowSeconds),
    maxRequestsPerIp: rateLimitMaxRequestsPerIp,
    maxRequestsPerUser: rateLimitMaxRequestsPerUser,
    runtimeConfigSnapshot: runtimeConfigSnapshot,
    authCredentialsStore: authCredentialsStore,
    rideRequestMetadataStore: rideRequestMetadataStore,
    operationalRecordStore: operationalRecordStore,
  ).buildHandler();

  final port = int.tryParse(Platform.environment['PORT'] ?? '8080') ?? 8080;
  stdout.writeln(
    'Hail-O startup: env=$environment db_mode=${config.dbMode.name} schema=${config.dbSchema} migration_head=$migrationHeadVersion metrics_public=$metricsPublic db_timeout_ms=$dbQueryTimeoutMs idle_timeout_s=$requestIdleTimeoutSeconds',
  );
  final server = await io.serve(handler, InternetAddress.anyIPv4, port);
  server.idleTimeout = Duration(seconds: requestIdleTimeoutSeconds);
  stdout.writeln(
    'Hail-O backend listening on http://${server.address.host}:${server.port}',
  );
}
