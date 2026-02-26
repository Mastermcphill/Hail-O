import 'dart:convert';
import 'dart:io';

import 'package:shelf/shelf.dart';
import 'package:shelf_router/shelf_router.dart';
import 'package:sqflite_common/sqlite_api.dart';

import '../../lib/domain/services/auth_service.dart';
import '../../lib/domain/services/dispatch_pricing_service.dart';
import '../../lib/domain/services/dispatch_trip_service.dart';
import '../../lib/domain/services/dispute_service.dart';
import '../../lib/domain/services/escrow_service.dart';
import '../../lib/domain/services/ride_api_flow_service.dart';
import '../../lib/domain/services/ride_settlement_service.dart';
import '../../lib/domain/services/ride_snapshot_service.dart';
import '../../lib/domain/services/wallet_reversal_service.dart';
import '../infra/analytics_event_store.dart';
import '../infra/audit_log_store.dart';
import '../infra/redis_client.dart';
import '../infra/request_context.dart';
import '../infra/postgres_provider.dart';
import '../infra/request_metrics.dart';
import '../infra/token_service.dart';
import '../jobs/job.dart';
import '../jobs/job_processor.dart';
import '../jobs/job_registry.dart';
import '../modules/admin/admin_controller.dart';
import '../modules/admin/admin_users_controller.dart';
import '../modules/auth/auth_credentials_store.dart';
import '../modules/auth/auth_controller.dart';
import '../modules/auth/phone_auth_service.dart';
import '../modules/auth/phone_auth_store.dart';
import '../modules/auth/sqlite_phone_auth_store.dart';
import '../modules/dispatch/dispatch_controller.dart';
import '../modules/disputes/disputes_controller.dart';
import '../modules/marketplace/billing_ledger_repository.dart';
import '../modules/marketplace/in_memory_marketplace_offer_repository.dart';
import '../modules/marketplace/marketplace_entitlement_service.dart';
import '../modules/marketplace/marketplace_reconciliation_service.dart';
import '../modules/marketplace/marketplace_repository.dart';
import '../modules/marketplace/marketplace_repository_memory.dart';
import '../modules/marketplace/marketplace_revenue_service.dart';
import '../modules/marketplace/marketplace_router.dart';
import '../modules/marketplace/marketplace_handlers.dart';
import '../modules/me/me_controller.dart';
import '../modules/marketplace/org_controller.dart';
import '../modules/marketplace/org_repository.dart';
import '../modules/marketplace/postgres_marketplace_offer_repository.dart';
import '../modules/routes/routes_controller.dart';
import '../modules/rides/ride_request_metadata_store.dart';
import '../modules/rides/rides_controller.dart';
import '../modules/settlement/settlement_controller.dart';
import '../modules/payments/payment_service.dart' as payments;
import '../modules/payments/payments_controller.dart';
import 'http_utils.dart';

Handler buildApiRouter({
  required Database? db,
  required TokenService tokenService,
  required String dbMode,
  required Future<bool> Function() dbHealthCheck,
  required Map<String, Object?> buildInfo,
  required RequestMetrics requestMetrics,
  required Map<String, Object?> runtimeConfigSnapshot,
  bool enableSentrySmokeEndpoint = false,
  PostgresProvider? postgresProvider,
  Map<String, String> environmentMap = const <String, String>{},
  bool metricsPublic = false,
  AuthCredentialsStore? authCredentialsStore,
  PhoneAuthStore? phoneAuthStore,
  RideRequestMetadataStore? rideRequestMetadataStore,
  OperationalRecordStore? operationalRecordStore,
  RedisQueueClient? redisClient,
  QueueJobRegistry? queueJobRegistry,
  QueueJobProcessor? queueJobProcessor,
}) {
  final env = environmentMap.isEmpty ? Platform.environment : environmentMap;
  final runtimeEnvironment = (env['ENV'] ?? env['FLIPTRYBE_ENV'] ?? 'unknown')
      .trim();
  final normalizedRuntimeEnvironment = runtimeEnvironment.trim().toLowerCase();
  final strictEnvironment = _isStrictEnvironment(normalizedRuntimeEnvironment);
  final essentialEnvReady =
      !strictEnvironment || (env['JWT_SECRET'] ?? '').trim().isNotEmpty;
  final redisConfigured = (env['REDIS_URL'] ?? '').trim().isNotEmpty;
  final auditLogStore = AuditLogStore(
    sqliteDb: db,
    postgresProvider: postgresProvider,
  );
  final analyticsEventStore = AnalyticsEventStore(
    sqliteDb: db,
    postgresProvider: postgresProvider,
  );

  final authService = db == null
      ? null
      : AuthService(db, externalStore: authCredentialsStore);
  final resolvedPhoneAuthStore =
      phoneAuthStore ?? (db == null ? null : SqlitePhoneAuthStore(db));
  final otpProviderConfigured = (env['OTP_PROVIDER'] ?? '').trim().isNotEmpty;
  final otpBypassConfigured = _parseBool(env['OTP_DEV_BYPASS']);
  final enablePhoneAuth =
      !_isProductionEnvironment(runtimeEnvironment) ||
      otpProviderConfigured ||
      otpBypassConfigured;
  final otpReady = _otpConfigReady(
    runtimeEnvironment: runtimeEnvironment,
    env: env,
  );
  final phoneAuthService = resolvedPhoneAuthStore == null
      ? null
      : !enablePhoneAuth
      ? null
      : PhoneAuthService.fromEnvironment(
          store: resolvedPhoneAuthStore,
          tokenService: tokenService,
          environment: runtimeEnvironment,
          envMap: env,
        );
  final authController = authService == null && phoneAuthService == null
      ? null
      : AuthController(
          authService: authService,
          tokenService: tokenService,
          phoneAuthService: phoneAuthService,
          analyticsEventStore: analyticsEventStore,
          otpRateLimitWindow: Duration(
            seconds: _readPositiveInt(
              env,
              'OTP_RATE_LIMIT_WINDOW_SECONDS',
              defaultValue: 600,
            ),
          ),
          otpRequestLimitPerIp: _readPositiveInt(
            env,
            'OTP_REQUEST_LIMIT_PER_IP',
            defaultValue: 6,
          ),
          otpRequestLimitPerPhone: _readPositiveInt(
            env,
            'OTP_REQUEST_LIMIT_PER_PHONE',
            defaultValue: 4,
          ),
          otpVerifyLimitPerIp: _readPositiveInt(
            env,
            'OTP_VERIFY_LIMIT_PER_IP',
            defaultValue: 12,
          ),
          otpVerifyLimitPerPhone: _readPositiveInt(
            env,
            'OTP_VERIFY_LIMIT_PER_PHONE',
            defaultValue: 8,
          ),
          redisClient: redisClient,
          warningSink: stderr.writeln,
        );
  final ridesController = db == null
      ? null
      : RidesController(
          db: db,
          rideApiFlowService: RideApiFlowService(
            db,
            externalMetadataStore: rideRequestMetadataStore,
            externalOperationalStore: operationalRecordStore,
          ),
          rideSnapshotService: RideSnapshotService(db),
        );
  final routesController = db == null ? null : RoutesController(db);
  final meController = db == null ? null : MeController(db);
  final dispatchController = db == null
      ? null
      : DispatchController(
          dispatchTripService: DispatchTripService(db),
          dispatchPricingService: DispatchPricingService(
            config: DispatchPricingConfig.fromEnvironment(env),
          ),
          auditLogStore: auditLogStore,
          analyticsEventStore: analyticsEventStore,
        );
  final settlementController = db == null
      ? null
      : SettlementController(
          rideSettlementService: RideSettlementService(db),
          escrowService: EscrowService(db),
        );
  final disputesController = db == null
      ? null
      : DisputesController(disputeService: DisputeService(db));
  final offerRepository = postgresProvider != null
      ? PostgresMarketplaceOfferRepository(postgresProvider)
      : InMemoryMarketplaceOfferRepository();
  final marketplaceRepository = postgresProvider != null
      ? PostgresMarketplaceRepository(postgresProvider)
      : InMemoryMarketplaceRepository();
  final orgRepository = postgresProvider != null
      ? PostgresOrgRepository(postgresProvider)
      : InMemoryOrgRepository();
  final entitlementRepository = postgresProvider != null
      ? PostgresMarketplaceEntitlementRepository(postgresProvider)
      : InMemoryMarketplaceEntitlementRepository();
  final entitlementService = MarketplaceEntitlementService(
    repository: entitlementRepository,
    postgresProvider: postgresProvider,
  );
  final billingLedgerRepository = postgresProvider != null
      ? PostgresBillingLedgerRepository(postgresProvider)
      : InMemoryBillingLedgerRepository();
  final paymentService = payments.PaymentService.fromEnvironment(
    postgresProvider: postgresProvider,
    billingLedgerRepository: billingLedgerRepository,
    offerRepository: offerRepository,
    entitlementService: entitlementService,
    configuredProvider: env['PAYMENTS_PROVIDER'] ?? env['PAYMENT_PROVIDER'],
    paystackSecretKey: env['PAYSTACK_SECRET_KEY'],
    paystackWebhookSecret: env['PAYSTACK_WEBHOOK_SECRET'],
    paystackApiBaseUrl: env['PAYSTACK_API_BASE_URL'],
    paystackCallbackUrl: env['PAYSTACK_CALLBACK_URL'],
    stripeWebhookSecret: env['STRIPE_WEBHOOK_SECRET'],
    metrics: requestMetrics,
    auditLogStore: auditLogStore,
    analyticsEventStore: analyticsEventStore,
  );
  queueJobRegistry?.register(QueueJobTypes.processWebhookEvent, (job) async {
    final provider = (job.payload['provider'] as String?)?.trim() ?? '';
    final providerEventId =
        (job.payload['provider_event_id'] as String?)?.trim() ?? '';
    if (provider.isEmpty || providerEventId.isEmpty) {
      throw const FormatException(
        'process_webhook_event requires provider and provider_event_id',
      );
    }
    await paymentService.processStoredWebhookEvent(
      provider: provider,
      providerEventId: providerEventId,
    );
  });
  queueJobRegistry?.register(QueueJobTypes.reconcilePayment, (_) async {
    await paymentService.retryPendingWebhooks(limit: 1);
  });
  final paymentsController = PaymentsController(
    paymentService: paymentService,
    environment: runtimeEnvironment,
    webhookSecret: (env['PAYMENTS_WEBHOOK_SECRET'] ?? '').trim(),
    paystackWebhookSecret: (env['PAYSTACK_WEBHOOK_SECRET'] ?? '').trim(),
    analyticsEventStore: analyticsEventStore,
    jobProcessor: queueJobProcessor,
  );
  final paymentsReady = _paymentsConfigReady(
    runtimeEnvironment: runtimeEnvironment,
    env: env,
  );
  final revenueService = MarketplaceRevenueService(
    postgresProvider: postgresProvider,
    metrics: requestMetrics,
  );
  final marketplaceHandlers = MarketplaceHandlers(
    offerRepository: offerRepository,
    paymentService: paymentService,
    entitlementService: entitlementService,
    revenueService: revenueService,
    orgRepository: orgRepository,
    analyticsEventStore: analyticsEventStore,
  );
  final marketplaceRouter = MarketplaceRouter(handlers: marketplaceHandlers);
  final marketplaceHandler = marketplaceRouter.router.call;
  final orgController = OrgController(
    orgRepository: orgRepository,
    marketplaceRepository: marketplaceRepository,
    billingLedgerRepository: billingLedgerRepository,
    entitlementService: entitlementService,
  );
  final orgApiHandler = Cascade()
      .add(orgController.router.call)
      .add(marketplaceRouter.orgRouter.call)
      .handler;
  final reconciliationService = postgresProvider == null
      ? null
      : MarketplaceReconciliationService(
          store: PostgresMarketplaceReconciliationStore(postgresProvider),
          entitlementService: entitlementService,
        );
  final adminController = AdminController(
    db: db,
    walletReversalService: db == null ? null : WalletReversalService(db),
    runtimeConfigSnapshot: runtimeConfigSnapshot,
    buildInfo: buildInfo,
    enableSentrySmokeEndpoint: enableSentrySmokeEndpoint,
    reconciliationService: reconciliationService,
    revenueService: revenueService,
    auditLogStore: auditLogStore,
    paymentService: paymentService,
    paystackSecretKey: (env['PAYSTACK_SECRET_KEY'] ?? '').trim(),
    paystackApiBaseUrl: (env['PAYSTACK_API_BASE_URL'] ?? '').trim(),
    analyticsEventStore: analyticsEventStore,
    queueJobProcessor: queueJobProcessor,
  );
  final adminUsersController = authService == null
      ? null
      : AdminUsersController(authService: authService);

  final router = Router()
    ..get('/', (Request request) {
      return Response.ok(
        jsonEncode({
          'ok': true,
          'service': 'hail-o-backend',
          'env': env['FLIPTRYBE_ENV'] ?? env['ENV'] ?? 'unknown',
          'commit': env['RENDER_GIT_COMMIT'] ?? 'unknown',
        }),
        headers: {'content-type': 'application/json'},
      );
    })
    ..get(
      '/health',
      (request) => _healthHandler(
        request,
        dbMode,
        dbHealthCheck,
        runtimeEnvironment,
        buildInfo,
        timeout: const Duration(milliseconds: 250),
      ),
    )
    ..get(
      '/api/healthz',
      (request) => _healthHandler(
        request,
        dbMode,
        dbHealthCheck,
        runtimeEnvironment,
        buildInfo,
        timeout: const Duration(seconds: 2),
      ),
    )
    ..get(
      '/healthz',
      (request) => _healthHandler(
        request,
        dbMode,
        dbHealthCheck,
        runtimeEnvironment,
        buildInfo,
        timeout: const Duration(seconds: 2),
      ),
    )
    ..get(
      '/ready',
      (request) => _readyHandler(
        request,
        dbMode: dbMode,
        dbHealthCheck: dbHealthCheck,
        buildInfo: buildInfo,
        sqliteDb: db,
        postgresProvider: postgresProvider,
        dbSchema: (env['DB_SCHEMA'] ?? 'public').trim(),
        essentialEnvReady: essentialEnvReady,
        paymentsReady: paymentsReady,
        otpReady: otpReady,
        redisClient: redisClient,
        redisConfigured: redisConfigured,
      ),
    )
    ..get(
      '/api/ready',
      (request) => _readyHandler(
        request,
        dbMode: dbMode,
        dbHealthCheck: dbHealthCheck,
        buildInfo: buildInfo,
        sqliteDb: db,
        postgresProvider: postgresProvider,
        dbSchema: (env['DB_SCHEMA'] ?? 'public').trim(),
        essentialEnvReady: essentialEnvReady,
        paymentsReady: paymentsReady,
        otpReady: otpReady,
        redisClient: redisClient,
        redisConfigured: redisConfigured,
      ),
    )
    ..get('/version', (request) => _versionHandler(buildInfo))
    ..get('/api/version', (request) => _versionHandler(buildInfo))
    ..get(
      '/metrics',
      (request) => _metricsHandler(request, requestMetrics, metricsPublic),
    )
    ..mount('/api/marketplace/', marketplaceHandler)
    ..mount('/marketplace/', marketplaceHandler)
    ..mount('/api/payments/', paymentsController.intentsRouter.call)
    ..mount('/payments/', paymentsController.intentsRouter.call)
    ..mount('/api/orgs', orgApiHandler)
    ..mount('/webhooks/', paymentsController.webhookRouter.call)
    ..mount('/admin/', adminController.router.call);
  if (authController != null) {
    router.mount('/auth/', authController.router.call);
  }
  if (meController != null) {
    router.mount('/me/', meController.router.call);
    router.mount('/me', meController.router.call);
  }
  if (dispatchController != null) {
    router.mount('/dispatch/', dispatchController.router.call);
    router.mount('/dispatch', dispatchController.router.call);
  }
  if (routesController != null) {
    router.mount('/routes/', routesController.router.call);
  }
  if (ridesController != null) {
    router.mount('/rides/', ridesController.router.call);
  }
  if (settlementController != null) {
    router.mount('/settlement/', settlementController.router.call);
  }
  if (disputesController != null) {
    router.mount('/disputes', disputesController.router.call);
  }
  if (adminUsersController != null) {
    router.post('/api/admin/users', adminUsersController.createUser);
  }
  router.all(
    '/<ignored|.*>',
    (request, _) => jsonErrorResponse(
      request,
      404,
      code: 'route_not_found',
      message: 'Route not found',
    ),
  );

  return router.call;
}

Future<Response> _readyHandler(
  Request request, {
  required String dbMode,
  required Future<bool> Function() dbHealthCheck,
  required Map<String, Object?> buildInfo,
  required Database? sqliteDb,
  required PostgresProvider? postgresProvider,
  required String dbSchema,
  required bool essentialEnvReady,
  required bool paymentsReady,
  required bool otpReady,
  required RedisQueueClient? redisClient,
  required bool redisConfigured,
}) async {
  bool dbOk;
  try {
    dbOk = await dbHealthCheck().timeout(
      const Duration(milliseconds: 750),
      onTimeout: () => false,
    );
  } catch (_) {
    dbOk = false;
  }

  final expectedMigrationHead =
      (buildInfo['migration_head'] as num?)?.toInt() ??
      int.tryParse((buildInfo['migration_head'] ?? '').toString());
  final appliedMigrationHead = await _readAppliedMigrationHead(
    dbMode: dbMode,
    sqliteDb: sqliteDb,
    postgresProvider: postgresProvider,
    dbSchema: dbSchema,
  );

  bool? migrationsMatch;
  if (expectedMigrationHead != null && appliedMigrationHead != null) {
    migrationsMatch = appliedMigrationHead == expectedMigrationHead;
  }

  final migrationsOk = migrationsMatch ?? true;
  final redisOk = !redisConfigured
      ? true
      : redisClient != null && await redisClient.ping();
  final isReady =
      dbOk &&
      migrationsOk &&
      essentialEnvReady &&
      paymentsReady &&
      otpReady &&
      redisOk;
  final payload = <String, Object?>{
    'ok': isReady,
    'service': 'hail-o-backend',
    'db_mode': dbMode,
    'db': dbOk,
    'db_ok': dbOk,
    'migrations_ok': migrationsOk,
    'essential_env_ready': essentialEnvReady,
    'payments_ready': paymentsReady,
    'otp_ready': otpReady,
    'redis': redisOk,
    'redis_ready': redisOk,
    'ready': isReady,
    if (expectedMigrationHead != null)
      'expected_migration_head': expectedMigrationHead,
    if (appliedMigrationHead != null)
      'applied_migration_head': appliedMigrationHead,
  };
  final traceId = request.requestContext.traceId.trim();
  if (traceId.isNotEmpty) {
    payload['trace_id'] = traceId;
  }
  return jsonResponse(isReady ? 200 : 503, payload);
}

Future<int?> _readAppliedMigrationHead({
  required String dbMode,
  required Database? sqliteDb,
  required PostgresProvider? postgresProvider,
  required String dbSchema,
}) async {
  try {
    if (dbMode.trim().toLowerCase() == 'sqlite') {
      final db = sqliteDb;
      if (db == null) {
        return null;
      }
      final tableRows = await db.rawQuery(
        'SELECT name FROM sqlite_master WHERE type = ? AND name = ? LIMIT 1',
        <Object>['table', 'schema_migrations'],
      );
      if (tableRows.isEmpty) {
        return null;
      }
      final rows = await db.rawQuery(
        'SELECT COALESCE(MAX(version), 0) AS head FROM schema_migrations',
      );
      if (rows.isEmpty) {
        return 0;
      }
      return (rows.first['head'] as num?)?.toInt() ?? 0;
    }
    final provider = postgresProvider;
    if (provider == null) {
      return null;
    }
    final normalizedSchema = _normalizeSchemaName(dbSchema);
    final qualifiedTable = '"$normalizedSchema".schema_migrations';
    final rows = await provider.withConnection(
      (connection) => connection.query(
        'SELECT COALESCE(MAX(version), 0)::int AS head FROM $qualifiedTable',
      ),
    );
    if (rows.isEmpty) {
      return 0;
    }
    return (rows.first.toColumnMap()['head'] as num?)?.toInt() ?? 0;
  } catch (_) {
    return null;
  }
}

String _normalizeSchemaName(String schema) {
  final normalized = schema.trim();
  if (normalized.isEmpty) {
    return 'public';
  }
  if (RegExp(r'^[A-Za-z_][A-Za-z0-9_]*$').hasMatch(normalized)) {
    return normalized;
  }
  return 'public';
}

Response _metricsHandler(
  Request request,
  RequestMetrics requestMetrics,
  bool metricsPublic,
) {
  if (!metricsPublic) {
    final role = (request.requestContext.role ?? '').trim().toLowerCase();
    if (role != 'admin') {
      return jsonErrorResponse(
        request,
        403,
        code: 'admin_only',
        message: 'Admin role required',
      );
    }
  }
  return jsonResponse(200, requestMetrics.snapshot());
}

Future<Response> _healthHandler(
  Request request,
  String dbMode,
  Future<bool> Function() dbHealthCheck,
  String environment,
  Map<String, Object?> buildInfo, {
  required Duration timeout,
}) async {
  bool dbOk;
  try {
    dbOk = await dbHealthCheck().timeout(timeout, onTimeout: () => false);
  } catch (_) {
    dbOk = false;
  }
  final normalizedEnvironment = environment.trim();
  final verboseRequested = _isTruthyQuery(
    request.url.queryParameters['verbose'],
  );
  final isProduction =
      normalizedEnvironment.toLowerCase() == 'production' ||
      normalizedEnvironment.toLowerCase() == 'prod';
  final allowVerbose = verboseRequested && !isProduction;
  final commit = (buildInfo['commit'] ?? '').toString().trim();
  final runtime = (buildInfo['runtime'] ?? '').toString().trim();
  final slimBuild = <String, Object?>{
    'commit': commit.isEmpty ? 'unknown' : commit,
    if (runtime.isNotEmpty) 'runtime': runtime,
  };
  final payload = <String, Object?>{
    'ok': dbOk,
    'service': 'hail-o-backend',
    'env': normalizedEnvironment.isEmpty ? 'unknown' : normalizedEnvironment,
    'db_mode': dbMode,
    'db_ok': dbOk,
    'build': allowVerbose ? buildInfo : slimBuild,
  };
  final traceId = request.requestContext.traceId.trim();
  if (traceId.isNotEmpty) {
    payload['trace_id'] = traceId;
  }
  return jsonResponse(dbOk ? 200 : 503, payload);
}

Response _versionHandler(Map<String, Object?> buildInfo) {
  final version = (buildInfo['version'] ?? 'unknown').toString();
  final commit = (buildInfo['commit'] ?? 'unknown').toString();
  return jsonResponse(200, <String, Object?>{
    'ok': true,
    'service': 'hail-o-backend',
    'version': version,
    'commit': commit,
    'build': buildInfo,
  });
}

bool _isTruthyQuery(String? value) {
  final normalized = value?.trim().toLowerCase() ?? '';
  return normalized == '1' || normalized == 'true' || normalized == 'yes';
}

bool _isProductionEnvironment(String value) {
  final normalized = value.trim().toLowerCase();
  return normalized == 'production' || normalized == 'prod';
}

bool _isStrictEnvironment(String value) {
  final normalized = value.trim().toLowerCase();
  return normalized == 'production' ||
      normalized == 'prod' ||
      normalized == 'staging';
}

bool _paymentsConfigReady({
  required String runtimeEnvironment,
  required Map<String, String> env,
}) {
  final provider = (env['PAYMENTS_PROVIDER'] ?? env['PAYMENT_PROVIDER'] ?? '')
      .trim()
      .toLowerCase();
  if (provider.isEmpty || provider == 'none' || provider == 'disabled') {
    return true;
  }
  final strict = _isStrictEnvironment(runtimeEnvironment);
  switch (provider) {
    case 'manual':
      if (!strict) {
        return true;
      }
      return (env['PAYMENTS_WEBHOOK_SECRET'] ?? '').trim().isNotEmpty;
    case 'paystack':
      return (env['PAYSTACK_SECRET_KEY'] ?? '').trim().isNotEmpty &&
          (env['PAYSTACK_WEBHOOK_SECRET'] ?? '').trim().isNotEmpty;
    case 'stripe':
      return (env['STRIPE_WEBHOOK_SECRET'] ?? '').trim().isNotEmpty;
    default:
      return false;
  }
}

bool _otpConfigReady({
  required String runtimeEnvironment,
  required Map<String, String> env,
}) {
  final normalizedEnv = runtimeEnvironment.trim().toLowerCase();
  final provider = (env['OTP_PROVIDER'] ?? '').trim().toLowerCase();
  final bypassEnabled = _parseBool(env['OTP_DEV_BYPASS']);
  final isProduction = _isProductionEnvironment(normalizedEnv);
  if (provider == 'termii') {
    final apiKey = (env['TERMII_API_KEY'] ?? '').trim();
    final senderId = (env['TERMII_SENDER_ID'] ?? '').trim();
    if (apiKey.isEmpty || senderId.isEmpty) {
      return false;
    }
    return !isProduction || !bypassEnabled;
  }
  if (provider.isEmpty || provider == 'none' || provider == 'disabled') {
    if (isProduction) {
      return false;
    }
    return true;
  }
  return false;
}

bool _parseBool(String? value) {
  final normalized = value?.trim().toLowerCase() ?? '';
  return normalized == '1' ||
      normalized == 'true' ||
      normalized == 'yes' ||
      normalized == 'y' ||
      normalized == 'on';
}

int _readPositiveInt(
  Map<String, String> env,
  String key, {
  required int defaultValue,
}) {
  final parsed = int.tryParse((env[key] ?? '').trim());
  if (parsed == null || parsed <= 0) {
    return defaultValue;
  }
  return parsed;
}
