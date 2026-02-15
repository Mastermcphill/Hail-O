import 'package:shelf/shelf.dart';
import 'package:hail_o_finance_core/sqlite_api.dart';

import '../infra/request_metrics.dart';
import '../infra/token_service.dart';
import '../modules/auth/auth_credentials_store.dart';
import '../modules/rides/ride_request_metadata_store.dart';
import 'middleware/auth_middleware.dart';
import 'middleware/cors_policy_middleware.dart';
import 'middleware/error_middleware.dart';
import 'middleware/idempotency_middleware.dart';
import 'middleware/observability_middleware.dart';
import 'middleware/rate_limit_middleware.dart';
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
    this.authCredentialsStore,
    this.rideRequestMetadataStore,
    this.operationalRecordStore,
  });

  final Database db;
  final TokenService tokenService;
  final String dbMode;
  final Future<bool> Function() dbHealthCheck;
  final Map<String, Object?> buildInfo;
  final String environment;
  final RequestMetrics requestMetrics;
  final Set<String> allowedOrigins;
  final bool metricsPublic;
  final AuthCredentialsStore? authCredentialsStore;
  final RideRequestMetadataStore? rideRequestMetadataStore;
  final OperationalRecordStore? operationalRecordStore;

  Handler buildHandler() {
    final router = buildApiRouter(
      db: db,
      tokenService: tokenService,
      authCredentialsStore: authCredentialsStore,
      rideRequestMetadataStore: rideRequestMetadataStore,
      operationalRecordStore: operationalRecordStore,
      dbMode: dbMode,
      dbHealthCheck: dbHealthCheck,
      buildInfo: buildInfo,
      requestMetrics: requestMetrics,
      metricsPublic: metricsPublic,
    );
    final authPublicPaths = <String>{
      'auth/register',
      'auth/login',
      'health',
      'api/healthz',
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
        .addMiddleware(idempotencyMiddleware())
        .addMiddleware(
          authMiddleware(tokenService, publicPaths: authPublicPaths),
        )
        .addMiddleware(rateLimitMiddleware())
        .addHandler(router);
  }
}
