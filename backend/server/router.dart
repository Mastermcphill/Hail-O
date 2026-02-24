import 'dart:convert';
import 'dart:io';

import 'package:shelf/shelf.dart';
import 'package:shelf_router/shelf_router.dart';
import 'package:sqflite_common/sqlite_api.dart';

import '../../lib/domain/services/auth_service.dart';
import '../../lib/domain/services/dispute_service.dart';
import '../../lib/domain/services/escrow_service.dart';
import '../../lib/domain/services/ride_api_flow_service.dart';
import '../../lib/domain/services/ride_settlement_service.dart';
import '../../lib/domain/services/ride_snapshot_service.dart';
import '../../lib/domain/services/wallet_reversal_service.dart';
import '../infra/request_context.dart';
import '../infra/postgres_provider.dart';
import '../infra/request_metrics.dart';
import '../infra/token_service.dart';
import '../modules/admin/admin_controller.dart';
import '../modules/auth/auth_credentials_store.dart';
import '../modules/auth/auth_controller.dart';
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
import '../modules/marketplace/org_controller.dart';
import '../modules/marketplace/org_repository.dart';
import '../modules/marketplace/postgres_marketplace_offer_repository.dart';
import '../modules/rides/ride_request_metadata_store.dart';
import '../modules/rides/rides_controller.dart';
import '../modules/settlement/settlement_controller.dart';
import '../modules/payments/payment_service.dart' as payments;
import '../modules/payments/payments_controller.dart';
import 'http_utils.dart';

Handler buildApiRouter({
  required Database db,
  required TokenService tokenService,
  required String dbMode,
  required Future<bool> Function() dbHealthCheck,
  required Map<String, Object?> buildInfo,
  required RequestMetrics requestMetrics,
  required Map<String, Object?> runtimeConfigSnapshot,
  PostgresProvider? postgresProvider,
  Map<String, String> environmentMap = const <String, String>{},
  bool metricsPublic = false,
  AuthCredentialsStore? authCredentialsStore,
  RideRequestMetadataStore? rideRequestMetadataStore,
  OperationalRecordStore? operationalRecordStore,
}) {
  final env = environmentMap.isEmpty ? Platform.environment : environmentMap;

  final authController = AuthController(
    authService: AuthService(db, externalStore: authCredentialsStore),
    tokenService: tokenService,
  );
  final ridesController = RidesController(
    rideApiFlowService: RideApiFlowService(
      db,
      externalMetadataStore: rideRequestMetadataStore,
      externalOperationalStore: operationalRecordStore,
    ),
    rideSnapshotService: RideSnapshotService(db),
  );
  final settlementController = SettlementController(
    rideSettlementService: RideSettlementService(db),
    escrowService: EscrowService(db),
  );
  final disputesController = DisputesController(
    disputeService: DisputeService(db),
  );
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
    entitlementService: entitlementService,
    configuredProvider: env['PAYMENT_PROVIDER'],
    paystackSecretKey: env['PAYSTACK_SECRET_KEY'],
    stripeWebhookSecret: env['STRIPE_WEBHOOK_SECRET'],
    metrics: requestMetrics,
  );
  final paymentsController = PaymentsController(paymentService: paymentService);
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
  );
  final marketplaceRouter = MarketplaceRouter(handlers: marketplaceHandlers);
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
    walletReversalService: WalletReversalService(db),
    runtimeConfigSnapshot: runtimeConfigSnapshot,
    buildInfo: buildInfo,
    reconciliationService: reconciliationService,
    revenueService: revenueService,
  );

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
      (request) => _healthHandler(request, dbMode, dbHealthCheck, buildInfo),
    )
    ..get(
      '/api/healthz',
      (request) => _healthHandler(request, dbMode, dbHealthCheck, buildInfo),
    )
    ..get(
      '/healthz',
      (request) => _healthHandler(request, dbMode, dbHealthCheck, buildInfo),
    )
    ..get(
      '/metrics',
      (request) => _metricsHandler(request, requestMetrics, metricsPublic),
    )
    ..mount('/auth/', authController.router.call)
    ..mount('/rides/', ridesController.router.call)
    ..mount('/settlement/', settlementController.router.call)
    ..mount('/disputes', disputesController.router.call)
    ..mount('/marketplace/', marketplaceRouter.router.call)
    ..mount('/api/orgs', orgApiHandler)
    ..mount('/webhooks/', paymentsController.router.call)
    ..mount('/admin/', adminController.router.call)
    ..all(
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
  Map<String, Object?> buildInfo,
) async {
  final dbOk = await dbHealthCheck();
  return jsonResponse(dbOk ? 200 : 503, <String, Object?>{
    'ok': dbOk,
    'service': 'hail-o-backend',
    'db_mode': dbMode,
    'db_ok': dbOk,
    'build': buildInfo,
  });
}
