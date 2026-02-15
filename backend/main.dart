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
  final config = BackendRuntimeConfig.fromEnvironment();
  final db = await DbProvider.instance.open(databasePath: config.sqlitePath);
  final requestMetrics = RequestMetrics();
  final environment = (Platform.environment['ENV'] ?? 'development').trim();
  final metricsPublic =
      (Platform.environment['METRICS_PUBLIC'] ?? 'false')
          .trim()
          .toLowerCase() ==
      'true';
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
    postgresProvider = PostgresProvider(databaseUrl, dbSchema: config.dbSchema);
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
  final allowedOrigins = parseAllowedOrigins(
    Platform.environment['ALLOWED_ORIGINS'],
  );
  final buildInfo = <String, Object?>{
    'commit': Platform.environment['RENDER_GIT_COMMIT'] ?? 'local',
    'runtime': 'dart_vm',
    'db_schema': config.dbSchema,
    'migration_head': migrationHeadVersion,
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
    authCredentialsStore: authCredentialsStore,
    rideRequestMetadataStore: rideRequestMetadataStore,
    operationalRecordStore: operationalRecordStore,
  ).buildHandler();

  final port = int.tryParse(Platform.environment['PORT'] ?? '8080') ?? 8080;
  stdout.writeln(
    'Hail-O startup: env=$environment db_mode=${config.dbMode.name} schema=${config.dbSchema} migration_head=$migrationHeadVersion metrics_public=$metricsPublic',
  );
  final server = await io.serve(handler, InternetAddress.anyIPv4, port);
  stdout.writeln(
    'Hail-O backend listening on http://${server.address.host}:${server.port}',
  );
}
