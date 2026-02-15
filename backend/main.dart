import 'dart:io';

import 'package:shelf/shelf_io.dart' as io;

import 'infra/db_provider.dart';
import 'infra/migrator.dart';
import 'infra/postgres_provider.dart';
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
import 'server/app_server.dart';

Future<void> main() async {
  final config = BackendRuntimeConfig.fromEnvironment();
  final db = await DbProvider.instance.open(databasePath: config.sqlitePath);
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
    postgresProvider = PostgresProvider(databaseUrl);
    await postgresProvider.open();
    await BackendPostgresMigrator(
      postgresProvider: postgresProvider,
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
        final connection = await postgresProvider!.open();
        final rows = await connection.query('SELECT 1');
        return rows.isNotEmpty;
      }
      final rows = await db.rawQuery('SELECT 1');
      return rows.isNotEmpty;
    } catch (_) {
      return false;
    }
  }

  final tokenService = TokenService.fromEnvironment();
  final handler = AppServer(
    db: db,
    tokenService: tokenService,
    dbMode: config.dbMode.name,
    dbHealthCheck: dbHealthCheck,
    authCredentialsStore: authCredentialsStore,
    rideRequestMetadataStore: rideRequestMetadataStore,
    operationalRecordStore: operationalRecordStore,
  ).buildHandler();

  final port = int.tryParse(Platform.environment['PORT'] ?? '8080') ?? 8080;
  final server = await io.serve(handler, InternetAddress.anyIPv4, port);
  stdout.writeln(
    'Hail-O backend listening on http://${server.address.host}:${server.port}',
  );
}
