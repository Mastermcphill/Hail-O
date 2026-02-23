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
  final db = await DbProvider.instance.open(
    databasePath: config.sqlitePath,
    dbMode: config.dbMode,
  );
  final requestMetrics = RequestMetrics();
  final environment = (env['ENV'] ?? 'development').trim();
  final dbQueryTimeoutMs =
      int.tryParse((env['DB_QUERY_TIMEOUT_MS'] ?? '10000').trim()) ?? 10000;
  final dbPoolSize = int.tryParse((env['DB_POOL_SIZE'] ?? '4').trim()) ?? 4;
  final requestIdleTimeoutSeconds =
      int.tryParse((env['REQUEST_IDLE_TIMEOUT_SECONDS'] ?? '30').trim()) ?? 30;
  final requestMaxBodyBytes =
      int.tryParse((env['REQUEST_MAX_BODY_BYTES'] ?? '262144').trim()) ??
      262144;
  final rateLimitEnabled =
      (env['RATE_LIMIT_ENABLED'] ?? 'true').trim().toLowerCase() != 'false';
  final rateLimitWindowSeconds =
      int.tryParse((env['RATE_LIMIT_WINDOW_SEC'] ?? '').trim()) ??
      int.tryParse((env['RATE_LIMIT_WINDOW_SECONDS'] ?? '60').trim()) ??
      60;
  final rateLimitMaxRequestsPerIp =
      int.tryParse((env['RATE_LIMIT_PER_IP_PER_MIN'] ?? '').trim()) ??
      int.tryParse((env['RATE_LIMIT_MAX_REQUESTS_PER_IP'] ?? '60').trim()) ??
      60;
  final rateLimitMaxRequestsPerUser =
      int.tryParse((env['RATE_LIMIT_PER_USER_PER_MIN'] ?? '').trim()) ??
      int.tryParse((env['RATE_LIMIT_MAX_REQUESTS_PER_USER'] ?? '120').trim()) ??
      120;
  final rateLimitAuthMaxRequestsPerIp =
      int.tryParse((env['RATE_LIMIT_BURST'] ?? '').trim()) ??
      int.tryParse((env['RATE_LIMIT_AUTH_PER_IP_PER_MIN'] ?? '20').trim()) ??
      20;
  final rateLimitAuthMaxRequestsPerUser =
      int.tryParse((env['RATE_LIMIT_AUTH_PER_USER_PER_MIN'] ?? '40').trim()) ??
      40;
  final rateLimitMarketplaceReadPerIp =
      int.tryParse(
        (env['RATE_LIMIT_MARKETPLACE_READ_PER_IP'] ?? '180').trim(),
      ) ??
      180;
  final rateLimitMarketplaceReadPerUser =
      int.tryParse(
        (env['RATE_LIMIT_MARKETPLACE_READ_PER_USER'] ?? '360').trim(),
      ) ??
      360;
  final rateLimitMarketplaceWritePerIp =
      int.tryParse(
        (env['RATE_LIMIT_MARKETPLACE_WRITE_PER_IP'] ?? '30').trim(),
      ) ??
      30;
  final rateLimitMarketplaceWritePerUser =
      int.tryParse(
        (env['RATE_LIMIT_MARKETPLACE_WRITE_PER_USER'] ?? '60').trim(),
      ) ??
      60;
  final rateLimitWebhookPerIp =
      int.tryParse((env['RATE_LIMIT_WEBHOOK_PER_IP'] ?? '600').trim()) ?? 600;
  final rateLimitWebhookPerUser =
      int.tryParse((env['RATE_LIMIT_WEBHOOK_PER_USER'] ?? '1200').trim()) ??
      1200;
  final trustProxyHeaders =
      (env['TRUST_PROXY_HEADERS'] ?? 'true').trim().toLowerCase() != 'false';
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
      poolSize: dbPoolSize,
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
    'runtime_marker': env['STARTUP_RUNTIME_MARKER'] ?? 'unknown',
    'dart_version': env['DART_SDK_VERSION'] ?? 'unknown',
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
    'rate_limit_window_sec': rateLimitWindowSeconds,
    'rate_limit_max_requests_per_ip': rateLimitMaxRequestsPerIp,
    'rate_limit_max_requests_per_user': rateLimitMaxRequestsPerUser,
    'rate_limit_auth_per_ip_per_min': rateLimitAuthMaxRequestsPerIp,
    'rate_limit_burst': rateLimitAuthMaxRequestsPerIp,
    'rate_limit_auth_per_user_per_min': rateLimitAuthMaxRequestsPerUser,
    'rate_limit_marketplace_read_per_ip': rateLimitMarketplaceReadPerIp,
    'rate_limit_marketplace_read_per_user': rateLimitMarketplaceReadPerUser,
    'rate_limit_marketplace_write_per_ip': rateLimitMarketplaceWritePerIp,
    'rate_limit_marketplace_write_per_user': rateLimitMarketplaceWritePerUser,
    'rate_limit_webhook_per_ip': rateLimitWebhookPerIp,
    'rate_limit_webhook_per_user': rateLimitWebhookPerUser,
    'trust_proxy_headers': trustProxyHeaders,
    'metrics_public': metricsPublic,
    'metrics_protected': !metricsPublic,
    'db_pool_size': dbPoolSize,
    'db_query_timeout_ms': dbQueryTimeoutMs,
    'request_idle_timeout_seconds': requestIdleTimeoutSeconds,
    'request_max_body_bytes': requestMaxBodyBytes,
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
    maxAuthRequestsPerIp: rateLimitAuthMaxRequestsPerIp,
    maxAuthRequestsPerUser: rateLimitAuthMaxRequestsPerUser,
    maxMarketplaceReadRequestsPerIp: rateLimitMarketplaceReadPerIp,
    maxMarketplaceReadRequestsPerUser: rateLimitMarketplaceReadPerUser,
    maxMarketplaceWriteRequestsPerIp: rateLimitMarketplaceWritePerIp,
    maxMarketplaceWriteRequestsPerUser: rateLimitMarketplaceWritePerUser,
    maxWebhookRequestsPerIp: rateLimitWebhookPerIp,
    maxWebhookRequestsPerUser: rateLimitWebhookPerUser,
    trustProxyHeaders: trustProxyHeaders,
    maxRequestBodyBytes: requestMaxBodyBytes,
    runtimeConfigSnapshot: runtimeConfigSnapshot,
    postgresProvider: postgresProvider,
    authCredentialsStore: authCredentialsStore,
    rideRequestMetadataStore: rideRequestMetadataStore,
    operationalRecordStore: operationalRecordStore,
  ).buildHandler();

  final configuredPortRaw = (Platform.environment['PORT'] ?? '').trim();
  final port = int.tryParse(configuredPortRaw) ?? 10000;
  stdout.writeln(
    'Hail-O startup: env=$environment db_mode=${config.dbMode.name} schema=${config.dbSchema} migration_head=$migrationHeadVersion metrics_public=$metricsPublic db_pool=$dbPoolSize db_timeout_ms=$dbQueryTimeoutMs idle_timeout_s=$requestIdleTimeoutSeconds max_body_bytes=$requestMaxBodyBytes',
  );
  stdout.writeln(
    'Port config: PORT=$configuredPortRaw resolved_port=$port bind_host=0.0.0.0',
  );
  stdout.writeln(
    'Rate limit config: enabled=$rateLimitEnabled window_sec=$rateLimitWindowSeconds per_ip=$rateLimitMaxRequestsPerIp per_user=$rateLimitMaxRequestsPerUser auth_burst=$rateLimitAuthMaxRequestsPerIp auth_user=$rateLimitAuthMaxRequestsPerUser marketplace_read_ip=$rateLimitMarketplaceReadPerIp marketplace_read_user=$rateLimitMarketplaceReadPerUser marketplace_write_ip=$rateLimitMarketplaceWritePerIp marketplace_write_user=$rateLimitMarketplaceWritePerUser webhook_ip=$rateLimitWebhookPerIp webhook_user=$rateLimitWebhookPerUser trust_proxy_headers=$trustProxyHeaders',
  );
  final server = await io.serve(handler, InternetAddress.anyIPv4, port);
  server.idleTimeout = Duration(seconds: requestIdleTimeoutSeconds);
  stdout.writeln(
    'Hail-O backend listening on http://${server.address.host}:${server.port}',
  );
}
