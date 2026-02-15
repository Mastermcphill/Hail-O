import 'package:shelf/shelf.dart';
import 'package:shelf_router/shelf_router.dart';
import 'package:hail_o_finance_core/sqlite_api.dart';

import '../../lib/domain/services/auth_service.dart';
import '../../lib/domain/services/dispute_service.dart';
import '../../lib/domain/services/ride_api_flow_service.dart';
import '../../lib/domain/services/ride_settlement_service.dart';
import '../../lib/domain/services/ride_snapshot_service.dart';
import '../../lib/domain/services/wallet_reversal_service.dart';
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
  );
  final disputesController = DisputesController(
    disputeService: DisputeService(db),
  );
  final adminController = AdminController(
    walletReversalService: WalletReversalService(db),
  );
  final driversController = DriversController();

  final router = Router()
    ..get(
      '/health',
      (request) => _healthHandler(request, dbMode, dbHealthCheck),
    )
    ..get(
      '/api/healthz',
      (request) => _healthHandler(request, dbMode, dbHealthCheck),
    )
    ..mount('/auth/', authController.router.call)
    ..mount('/rides/', ridesController.router.call)
    ..mount('/drivers/', driversController.router.call)
    ..mount('/settlement/', settlementController.router.call)
    ..mount('/disputes', disputesController.router.call)
    ..mount('/admin/', adminController.router.call);

  return router.call;
}

Future<Response> _healthHandler(
  Request request,
  String dbMode,
  Future<bool> Function() dbHealthCheck,
) async {
  final dbOk = await dbHealthCheck();
  return jsonResponse(dbOk ? 200 : 503, <String, Object?>{
    'ok': dbOk,
    'service': 'hail-o-backend',
    'db_mode': dbMode,
    'db_ok': dbOk,
  });
}
