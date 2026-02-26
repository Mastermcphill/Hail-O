import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:shelf/shelf.dart';
import 'package:shelf/shelf_io.dart' as io;
import 'package:sqflite_common/sqlite_api.dart';

import 'infra/db_provider.dart';
import 'infra/migrator.dart';
import 'infra/postgres_provider.dart';
import 'infra/production_config_validator.dart';
import 'infra/request_metrics.dart';
import 'infra/runtime_config.dart';
import 'infra/sentry_observability.dart';
import 'infra/token_service.dart';
import 'modules/auth/auth_credentials_store.dart';
import 'modules/auth/postgres_auth_credentials_store.dart';
import 'modules/auth/postgres_phone_auth_store.dart';
import 'modules/auth/sqlite_auth_credentials_store.dart';
import 'modules/auth/sqlite_phone_auth_store.dart';
import 'modules/auth/phone_auth_store.dart';
import 'modules/rides/postgres_operational_record_store.dart';
import 'modules/rides/postgres_ride_request_metadata_store.dart';
import 'modules/rides/ride_request_metadata_store.dart';
import 'modules/rides/sqlite_operational_record_store.dart';
import 'modules/rides/sqlite_ride_request_metadata_store.dart';
import 'server/middleware/cors_policy_middleware.dart';
import 'server/app_server.dart';

class BackendDatabaseRuntime {
  const BackendDatabaseRuntime({
    required this.usePostgres,
    required this.dbPoolSize,
    required this.dbQueryTimeoutMs,
    this.sqliteDb,
    this.postgresProvider,
  });

  final bool usePostgres;
  final int dbPoolSize;
  final int dbQueryTimeoutMs;
  final Database? sqliteDb;
  final PostgresProvider? postgresProvider;
}

Future<BackendDatabaseRuntime> openBackendDatabaseRuntime({
  required BackendRuntimeConfig config,
  required Map<String, String> env,
  DbProvider? dbProvider,
}) async {
  final provider = dbProvider ?? DbProvider.instance;
  final dbQueryTimeoutMs =
      int.tryParse((env['DB_QUERY_TIMEOUT_MS'] ?? '10000').trim()) ?? 10000;
  final dbPoolSize = int.tryParse((env['DB_POOL_SIZE'] ?? '4').trim()) ?? 4;
  final dbHandle = await provider.open(
    databasePath: config.sqlitePath,
    dbMode: config.dbMode,
    databaseUrl: config.databaseUrl,
    dbSchema: config.dbSchema,
    poolSize: dbPoolSize,
    statementTimeoutMs: dbQueryTimeoutMs,
  );
  final Database? sqliteDb = dbHandle.sqliteDatabase;
  final PostgresProvider? postgresProvider = dbHandle.postgresProvider;
  final bool usePostgres = config.usePostgres;
  if (!usePostgres && sqliteDb == null) {
    throw StateError('BACKEND_DB_MODE=sqlite requires sqlite database.');
  }
  if (usePostgres && postgresProvider == null) {
    throw StateError('BACKEND_DB_MODE=postgres requires postgres provider.');
  }
  return BackendDatabaseRuntime(
    usePostgres: usePostgres,
    dbPoolSize: dbPoolSize,
    dbQueryTimeoutMs: dbQueryTimeoutMs,
    sqliteDb: sqliteDb,
    postgresProvider: postgresProvider,
  );
}

Future<void> main() async {
  final bootstrapEnv = Platform.environment;
  final bootstrapEnvironment = (bootstrapEnv['ENV'] ?? 'development').trim();
  await BackendSentryObservability.configure(
    dsn: (bootstrapEnv['SENTRY_DSN'] ?? '').trim(),
    environment: bootstrapEnvironment,
    release: (bootstrapEnv['RENDER_GIT_COMMIT'] ?? 'local').trim(),
  );

  await runZonedGuarded(
    () async {
      final env = Platform.environment;
      final config = BackendRuntimeConfig.fromEnvironment();
      final environment = (env['ENV'] ?? 'development').trim();
      validateProductionConfig(
        environment: environment,
        usePostgres: config.usePostgres,
        envMap: env,
      );
      final dbRuntime = await openBackendDatabaseRuntime(
        config: config,
        env: env,
      );
      final bool usePostgres = dbRuntime.usePostgres;
      final int dbPoolSize = dbRuntime.dbPoolSize;
      final int dbQueryTimeoutMs = dbRuntime.dbQueryTimeoutMs;
      final Database? sqliteDb = dbRuntime.sqliteDb;
      final PostgresProvider? postgresProvider = dbRuntime.postgresProvider;
      final requestMetrics = RequestMetrics();
      final requestIdleTimeoutSeconds =
          int.tryParse((env['REQUEST_IDLE_TIMEOUT_SECONDS'] ?? '30').trim()) ??
          30;
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
          int.tryParse(
            (env['RATE_LIMIT_MAX_REQUESTS_PER_IP'] ?? '60').trim(),
          ) ??
          60;
      final rateLimitMaxRequestsPerUser =
          int.tryParse((env['RATE_LIMIT_PER_USER_PER_MIN'] ?? '').trim()) ??
          int.tryParse(
            (env['RATE_LIMIT_MAX_REQUESTS_PER_USER'] ?? '120').trim(),
          ) ??
          120;
      final rateLimitAuthMaxRequestsPerIp =
          int.tryParse((env['RATE_LIMIT_BURST'] ?? '').trim()) ??
          int.tryParse(
            (env['RATE_LIMIT_AUTH_PER_IP_PER_MIN'] ?? '12').trim(),
          ) ??
          12;
      final rateLimitAuthMaxRequestsPerUser =
          int.tryParse(
            (env['RATE_LIMIT_AUTH_PER_USER_PER_MIN'] ?? '24').trim(),
          ) ??
          24;
      final rateLimitMarketplaceReadPerIp =
          int.tryParse(
            (env['RATE_LIMIT_MARKETPLACE_READ_PER_IP'] ?? '120').trim(),
          ) ??
          120;
      final rateLimitMarketplaceReadPerUser =
          int.tryParse(
            (env['RATE_LIMIT_MARKETPLACE_READ_PER_USER'] ?? '240').trim(),
          ) ??
          240;
      final rateLimitMarketplaceWritePerIp =
          int.tryParse(
            (env['RATE_LIMIT_MARKETPLACE_WRITE_PER_IP'] ?? '40').trim(),
          ) ??
          40;
      final rateLimitMarketplaceWritePerUser =
          int.tryParse(
            (env['RATE_LIMIT_MARKETPLACE_WRITE_PER_USER'] ?? '80').trim(),
          ) ??
          80;
      final rateLimitWebhookPerIp =
          int.tryParse((env['RATE_LIMIT_WEBHOOK_PER_IP'] ?? '300').trim()) ??
          300;
      final rateLimitWebhookPerUser =
          int.tryParse((env['RATE_LIMIT_WEBHOOK_PER_USER'] ?? '').trim()) ??
          int.tryParse(
            (env['RATE_LIMIT_WEBHOOK_MAX_REQUESTS_PER_USER'] ?? '').trim(),
          ) ??
          rateLimitMaxRequestsPerUser;
      final trustProxyHeaders =
          (env['TRUST_PROXY_HEADERS'] ?? 'true').trim().toLowerCase() !=
          'false';
      final metricsPublic =
          (env['METRICS_PUBLIC'] ?? 'false').trim().toLowerCase() == 'true';
      final enableSentrySmokeEndpoint =
          (env['ADMIN_ENABLE_SENTRY_SMOKE_ENDPOINT'] ?? 'false')
              .trim()
              .toLowerCase() ==
          'true';
      final migrationHeadVersion =
          BackendPostgresMigrator.migrationHeadVersion();
      late final AuthCredentialsStore authCredentialsStore;
      late final PhoneAuthStore phoneAuthStore;
      late final RideRequestMetadataStore rideRequestMetadataStore;
      late final OperationalRecordStore operationalRecordStore;

      if (usePostgres) {
        final provider = postgresProvider!;
        await BackendPostgresMigrator(
          postgresProvider: provider,
          dbSchema: config.dbSchema,
        ).runPendingMigrations();
        authCredentialsStore = PostgresAuthCredentialsStore(provider);
        phoneAuthStore = PostgresPhoneAuthStore(provider);
        rideRequestMetadataStore = PostgresRideRequestMetadataStore(provider);
        operationalRecordStore = PostgresOperationalRecordStore(provider);
      } else {
        final sqliteDatabase = sqliteDb!;
        authCredentialsStore = SqliteAuthCredentialsStore(sqliteDatabase);
        phoneAuthStore = SqlitePhoneAuthStore(sqliteDatabase);
        rideRequestMetadataStore = SqliteRideRequestMetadataStore(
          sqliteDatabase,
        );
        operationalRecordStore = const SqliteOperationalRecordStore();
      }

      Future<bool> dbHealthCheck() async {
        try {
          if (usePostgres) {
            final rows = await postgresProvider!.withConnection(
              (connection) => connection.query('SELECT 1'),
            );
            return rows.isNotEmpty;
          }
          final rows = await sqliteDb!.rawQuery('SELECT 1');
          return rows.isNotEmpty;
        } catch (_) {
          return false;
        }
      }

      final tokenService = TokenService.fromEnvironment();
      final allowedOrigins = parseAllowedOrigins(env['ALLOWED_ORIGINS']);
      final buildInfo = <String, Object?>{
        'version': env['RENDER_GIT_TAG'] ?? env['BUILD_VERSION'] ?? 'local',
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
        'rate_limit_marketplace_write_per_user':
            rateLimitMarketplaceWritePerUser,
        'rate_limit_webhook_per_ip': rateLimitWebhookPerIp,
        'rate_limit_webhook_per_user': rateLimitWebhookPerUser,
        'trust_proxy_headers': trustProxyHeaders,
        'metrics_public': metricsPublic,
        'metrics_protected': !metricsPublic,
        'admin_enable_sentry_smoke_endpoint': enableSentrySmokeEndpoint,
        'db_pool_size': dbPoolSize,
        'db_query_timeout_ms': dbQueryTimeoutMs,
        'request_idle_timeout_seconds': requestIdleTimeoutSeconds,
        'request_max_body_bytes': requestMaxBodyBytes,
      };
      final handler = AppServer(
        db: sqliteDb,
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
        enableSentrySmokeEndpoint: enableSentrySmokeEndpoint,
        runtimeConfigSnapshot: runtimeConfigSnapshot,
        postgresProvider: postgresProvider,
        authCredentialsStore: authCredentialsStore,
        phoneAuthStore: phoneAuthStore,
        rideRequestMetadataStore: rideRequestMetadataStore,
        operationalRecordStore: operationalRecordStore,
        environmentMap: env,
      ).buildHandler();

      const host = '0.0.0.0';
      final port = int.parse(Platform.environment['PORT'] ?? '8080');
      stderr.writeln(
        "BIND: host=$host port=$port envPORT=${Platform.environment['PORT']}",
      );
      stdout.writeln(
        'Hail-O startup: env=$environment db_mode=${config.dbMode.name} schema=${config.dbSchema} migration_head=$migrationHeadVersion metrics_public=$metricsPublic sentry_smoke_endpoint=$enableSentrySmokeEndpoint db_pool=$dbPoolSize db_timeout_ms=$dbQueryTimeoutMs idle_timeout_s=$requestIdleTimeoutSeconds max_body_bytes=$requestMaxBodyBytes',
      );
      stdout.writeln(
        'Rate limit config: enabled=$rateLimitEnabled window_sec=$rateLimitWindowSeconds per_ip=$rateLimitMaxRequestsPerIp per_user=$rateLimitMaxRequestsPerUser auth_burst=$rateLimitAuthMaxRequestsPerIp auth_user=$rateLimitAuthMaxRequestsPerUser marketplace_read_ip=$rateLimitMarketplaceReadPerIp marketplace_read_user=$rateLimitMarketplaceReadPerUser marketplace_write_ip=$rateLimitMarketplaceWritePerIp marketplace_write_user=$rateLimitMarketplaceWritePerUser webhook_ip=$rateLimitWebhookPerIp webhook_user=$rateLimitWebhookPerUser trust_proxy_headers=$trustProxyHeaders',
      );
      late final HttpServer server;
      try {
        server = await io.serve(handler, host, port);
        stderr.writeln('LISTENING: http://$host:$port');
      } catch (error, stackTrace) {
        stderr.writeln('BIND FAILED: $error');
        stderr.writeln(stackTrace);
        rethrow;
      }
      server.idleTimeout = Duration(seconds: requestIdleTimeoutSeconds);
      stdout.writeln('Listening on $host:$port');

      try {
        await _verifyBindContract(port: server.port);
        stdout.writeln(
          jsonEncode(<String, Object?>{
            'event': 'bind_check_ok',
            'path': '/api/healthz',
            'port': server.port,
          }),
        );
      } catch (error) {
        stdout.writeln(
          jsonEncode(<String, Object?>{
            'event': 'bind_check_failed',
            'path': '/api/healthz',
            'port': server.port,
            'reason': error.toString(),
          }),
        );
        await server.close(force: true);
        await DbProvider.instance.close();
        rethrow;
      }
      try {
        final shutdownCompleter = Completer<void>();
        final signalSubscriptions = <StreamSubscription<ProcessSignal>>[];

        Future<void> triggerShutdown(String signal) async {
          if (shutdownCompleter.isCompleted) {
            return;
          }
          stdout.writeln(
            jsonEncode(<String, Object?>{
              'event': 'shutdown_signal',
              'signal': signal,
            }),
          );
          await server.close(force: false);
          shutdownCompleter.complete();
        }

        if (!Platform.isWindows) {
          signalSubscriptions.add(
            ProcessSignal.sigterm.watch().listen(
              (_) => unawaited(triggerShutdown('sigterm')),
            ),
          );
        }
        signalSubscriptions.add(
          ProcessSignal.sigint.watch().listen(
            (_) => unawaited(triggerShutdown('sigint')),
          ),
        );

        await shutdownCompleter.future;
        for (final subscription in signalSubscriptions) {
          await subscription.cancel();
        }
      } finally {
        await DbProvider.instance.close();
      }
    },
    (error, stackTrace) {
      unawaited(
        BackendSentryObservability.captureException(
          error,
          stackTrace,
          source: 'backend_main',
        ),
      );
      stderr.writeln('FATAL: $error');
      stderr.writeln(stackTrace);
      exitCode = 1;
    },
  );
}

typedef ServerBinder = Future<HttpServer> Function(String host, int port);
typedef RequestServer = void Function(HttpServer server, Handler handler);
typedef BindErrorReporter =
    Future<void> Function(Object error, StackTrace stackTrace);
typedef ExitProcess = void Function(int exitCode);
typedef EventLogger = void Function(Map<String, Object?> event);

Future<HttpServer> bindServerOrExit({
  required Handler handler,
  required String host,
  required int port,
  ServerBinder binder = _defaultServerBinder,
  RequestServer serveRequests = _defaultServeRequests,
  BindErrorReporter reportError = _defaultBindErrorReporter,
  EventLogger logEvent = _defaultEventLogger,
  ExitProcess exitProcess = _defaultExitProcess,
}) async {
  try {
    final server = await binder(host, port);
    serveRequests(server, handler);
    logEvent(<String, Object?>{
      'event': 'server_listen',
      'host': host,
      'port': port,
    });
    return server;
  } catch (error, stackTrace) {
    logEvent(<String, Object?>{
      'event': 'server_bind_failed',
      'host': host,
      'port': port,
      'error': error.toString(),
    });
    await reportError(error, stackTrace);
    exitProcess(1);
    throw _ServerBindFailure(error);
  }
}

Future<void> _verifyBindContract({required int port}) async {
  final client = HttpClient();
  client.connectionTimeout = const Duration(seconds: 3);
  try {
    final request = await client
        .getUrl(Uri.parse('http://127.0.0.1:$port/api/healthz'))
        .timeout(const Duration(seconds: 5));
    request.headers.set(HttpHeaders.acceptHeader, 'application/json');
    final response = await request.close().timeout(const Duration(seconds: 5));
    final body = await utf8.decoder.bind(response).join();
    if (response.statusCode != 200) {
      throw StateError(
        'bind contract expected 200 from /api/healthz, got ${response.statusCode}, body=$body',
      );
    }
  } finally {
    client.close(force: true);
  }
}

Future<HttpServer> _defaultServerBinder(String host, int port) {
  return HttpServer.bind(host, port);
}

void _defaultServeRequests(HttpServer server, Handler handler) {
  io.serveRequests(server, handler);
}

Future<void> _defaultBindErrorReporter(Object error, StackTrace stackTrace) {
  return BackendSentryObservability.captureException(
    error,
    stackTrace,
    source: 'server_bind',
  );
}

void _defaultEventLogger(Map<String, Object?> event) {
  stdout.writeln(jsonEncode(event));
}

void _defaultExitProcess(int exitCodeValue) {
  exit(exitCodeValue);
}

class _ServerBindFailure implements Exception {
  _ServerBindFailure(this.error);

  final Object error;

  @override
  String toString() => 'ServerBindFailure($error)';
}
