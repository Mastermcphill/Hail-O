import 'package:shelf/shelf.dart';
import 'package:shelf_router/shelf_router.dart';
import 'package:hail_o_finance_core/sqlite_api.dart';

import '../../lib/domain/services/auth_service.dart';
import '../../lib/domain/services/dispute_service.dart';
import '../../lib/domain/services/escrow_service.dart';
import '../../lib/domain/services/ride_api_flow_service.dart';
import '../../lib/domain/services/ride_settlement_service.dart';
import '../../lib/domain/services/ride_snapshot_service.dart';
import '../../lib/domain/services/wallet_reversal_service.dart';
import '../infra/request_context.dart';
import '../infra/request_metrics.dart';
import '../infra/token_service.dart';
import '../modules/auth/auth_credentials_store.dart';
import '../modules/admin/admin_controller.dart';
import '../modules/auth/auth_controller.dart';
import '../modules/disputes/disputes_controller.dart';
import '../modules/drivers/drivers_controller.dart';
import '../modules/rides/ride_request_metadata_store.dart';
import '../modules/rides/rides_controller.dart';
import '../modules/settlement/settlement_controller.dart';
import 'http_utils.dart';

Handler buildApiRouter({
  required Database db,
  required TokenService tokenService,
  required String dbMode,
  required Future<bool> Function() dbHealthCheck,
  required Map<String, Object?> buildInfo,
  required RequestMetrics requestMetrics,
  required Map<String, Object?> runtimeConfigSnapshot,
  bool metricsPublic = false,
  AuthCredentialsStore? authCredentialsStore,
  RideRequestMetadataStore? rideRequestMetadataStore,
  OperationalRecordStore? operationalRecordStore,
}) {
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
  final adminController = AdminController(
    walletReversalService: WalletReversalService(db),
    runtimeConfigSnapshot: runtimeConfigSnapshot,
  );
  final driversController = DriversController();

  final router = Router()
    ..get(
      '/health',
      (request) => _healthHandler(request, dbMode, dbHealthCheck, buildInfo),
    )
    ..get(
      '/api/healthz',
      (request) => _healthHandler(request, dbMode, dbHealthCheck, buildInfo),
    )
    ..get(
      '/metrics',
      (request) => _metricsHandler(request, requestMetrics, metricsPublic),
    )
    ..mount('/auth/', authController.router.call)
    ..mount('/rides/', ridesController.router.call)
    ..mount('/drivers/', driversController.router.call)
    ..mount('/settlement/', settlementController.router.call)
    ..mount('/disputes', disputesController.router.call)
    ..mount('/admin/', adminController.router.call);

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
