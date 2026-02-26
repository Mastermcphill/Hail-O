import 'dart:io';

import 'package:shelf/shelf.dart';
import 'package:sqflite_common/sqlite_api.dart';

import '../infra/postgres_provider.dart';
import '../infra/request_metrics.dart';
import '../infra/token_service.dart';
import '../modules/auth/auth_credentials_store.dart';
import '../modules/auth/phone_auth_store.dart';
import '../modules/rides/ride_request_metadata_store.dart';
import 'middleware/auth_middleware.dart';
import 'middleware/admin_emergency_access_middleware.dart';
import 'middleware/cors_policy_middleware.dart';
import 'middleware/error_middleware.dart';
import 'middleware/idempotency_middleware.dart';
import 'middleware/observability_middleware.dart';
import 'middleware/rate_limit_middleware.dart';
import 'middleware/disabled_user_middleware.dart';
import 'middleware/request_size_middleware.dart';
import 'middleware/security_headers_middleware.dart';
import 'middleware/trace_middleware.dart';
import 'router.dart';

class AppServer {
  const AppServer({
    required this.db,
    required this.tokenService,
    required this.dbMode,
    required this.dbHealthCheck,
    required this.buildInfo,
    required this.environment,
    required this.requestMetrics,
    this.allowedOrigins = const <String>{},
    this.metricsPublic = false,
    this.rateLimitEnabled = true,
    this.rateLimitWindow = const Duration(minutes: 1),
    this.maxRequestsPerIp = 60,
    this.maxRequestsPerUser = 120,
    this.maxAuthRequestsPerIp = 20,
    this.maxAuthRequestsPerUser = 40,
    this.maxMarketplaceReadRequestsPerIp = 120,
    this.maxMarketplaceReadRequestsPerUser = 240,
    this.maxMarketplaceWriteRequestsPerIp = 40,
    this.maxMarketplaceWriteRequestsPerUser = 80,
    this.maxWebhookRequestsPerIp = 300,
    this.maxWebhookRequestsPerUser = 120,
    this.trustProxyHeaders = true,
    this.maxRequestBodyBytes = 262144,
    this.enableSentrySmokeEndpoint = false,
    this.runtimeConfigSnapshot = const <String, Object?>{},
    this.postgresProvider,
    this.authCredentialsStore,
    this.phoneAuthStore,
    this.rideRequestMetadataStore,
    this.operationalRecordStore,
    this.environmentMap = const <String, String>{},
  });

  final Database? db;
  final TokenService tokenService;
  final String dbMode;
  final Future<bool> Function() dbHealthCheck;
  final Map<String, Object?> buildInfo;
  final String environment;
  final RequestMetrics requestMetrics;
  final Set<String> allowedOrigins;
  final bool metricsPublic;
  final bool rateLimitEnabled;
  final Duration rateLimitWindow;
  final int maxRequestsPerIp;
  final int maxRequestsPerUser;
  final int maxAuthRequestsPerIp;
  final int maxAuthRequestsPerUser;
  final int maxMarketplaceReadRequestsPerIp;
  final int maxMarketplaceReadRequestsPerUser;
  final int maxMarketplaceWriteRequestsPerIp;
  final int maxMarketplaceWriteRequestsPerUser;
  final int maxWebhookRequestsPerIp;
  final int maxWebhookRequestsPerUser;
  final bool trustProxyHeaders;
  final int maxRequestBodyBytes;
  final bool enableSentrySmokeEndpoint;
  final Map<String, Object?> runtimeConfigSnapshot;
  final PostgresProvider? postgresProvider;
  final AuthCredentialsStore? authCredentialsStore;
  final PhoneAuthStore? phoneAuthStore;
  final RideRequestMetadataStore? rideRequestMetadataStore;
  final OperationalRecordStore? operationalRecordStore;
  final Map<String, String> environmentMap;

  Handler buildHandler() {
    final env = environmentMap.isEmpty ? Platform.environment : environmentMap;
    final adminToken = (env['ADMIN_TOKEN'] ?? '').trim();
    final router = buildApiRouter(
      db: db,
      tokenService: tokenService,
      authCredentialsStore: authCredentialsStore,
      phoneAuthStore: phoneAuthStore,
      rideRequestMetadataStore: rideRequestMetadataStore,
      operationalRecordStore: operationalRecordStore,
      dbMode: dbMode,
      dbHealthCheck: dbHealthCheck,
      buildInfo: buildInfo,
      requestMetrics: requestMetrics,
      metricsPublic: metricsPublic,
      runtimeConfigSnapshot: runtimeConfigSnapshot,
      enableSentrySmokeEndpoint: enableSentrySmokeEndpoint,
      postgresProvider: postgresProvider,
      environmentMap: environmentMap,
    );
    final authPublicPaths = <String>{
      'auth/register',
      'auth/login',
      'auth/otp/request',
      'auth/otp/verify',
      'auth/token/refresh',
      'health',
      'healthz',
      'api/healthz',
      'version',
      'api/version',
      'webhooks/payments',
      if (metricsPublic) 'metrics',
    };
    return Pipeline()
        .addMiddleware(
          securityHeadersMiddleware(
            enableStrictTransportSecurity:
                environment.trim().toLowerCase() == 'production',
          ),
        )
        .addMiddleware(traceMiddleware())
        .addMiddleware(observabilityMiddleware(metrics: requestMetrics))
        .addMiddleware(errorMiddleware())
        .addMiddleware(corsPolicyMiddleware(allowedOrigins: allowedOrigins))
        .addMiddleware(requestSizeMiddleware(maxBytes: maxRequestBodyBytes))
        .addMiddleware(idempotencyMiddleware())
        .addMiddleware(adminEmergencyAccessMiddleware(adminToken: adminToken))
        .addMiddleware(
          authMiddleware(tokenService, publicPaths: authPublicPaths),
        )
        .addMiddleware(
          disabledUserMiddleware(db: db, postgresProvider: postgresProvider),
        )
        .addHandler(
          rateLimitEnabled
              ? Pipeline()
                    .addMiddleware(
                      rateLimitMiddleware(
                        window: rateLimitWindow,
                        maxRequestsPerIp: maxRequestsPerIp,
                        maxRequestsPerUser: maxRequestsPerUser,
                        maxAuthRequestsPerIp: maxAuthRequestsPerIp,
                        maxAuthRequestsPerUser: maxAuthRequestsPerUser,
                        maxMarketplaceReadRequestsPerIp:
                            maxMarketplaceReadRequestsPerIp,
                        maxMarketplaceReadRequestsPerUser:
                            maxMarketplaceReadRequestsPerUser,
                        maxMarketplaceWriteRequestsPerIp:
                            maxMarketplaceWriteRequestsPerIp,
                        maxMarketplaceWriteRequestsPerUser:
                            maxMarketplaceWriteRequestsPerUser,
                        maxWebhookRequestsPerIp: maxWebhookRequestsPerIp,
                        maxWebhookRequestsPerUser: maxWebhookRequestsPerUser,
                        trustProxyHeaders: trustProxyHeaders,
                      ),
                    )
                    .addHandler(router)
              : router,
        );
  }
}
