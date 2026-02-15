import 'package:hail_o_finance_core/domain/services/auth_service.dart';
import 'package:hail_o_finance_core/domain/services/dispute_service.dart';
import 'package:hail_o_finance_core/domain/services/ride_api_flow_service.dart';
import 'package:hail_o_finance_core/domain/services/ride_settlement_service.dart';
import 'package:hail_o_finance_core/domain/services/ride_snapshot_service.dart';
import 'package:hail_o_finance_core/domain/services/wallet_reversal_service.dart';
import 'package:hail_o_finance_core/sqlite_api.dart';
import 'package:shelf/shelf.dart';
import 'package:shelf_router/shelf_router.dart';

import '../infra/token_service.dart';
import '../modules/admin/admin_controller.dart';
import '../modules/auth/auth_controller.dart';
import '../modules/disputes/disputes_controller.dart';
import '../modules/drivers/drivers_controller.dart';
import '../modules/rides/rides_controller.dart';
import '../modules/settlement/settlement_controller.dart';
import 'http_utils.dart';

Handler buildApiRouter({
  required Database db,
  required TokenService tokenService,
}) {
  final authController = AuthController(
    authService: AuthService(db),
    tokenService: tokenService,
  );
  final ridesController = RidesController(
    rideApiFlowService: RideApiFlowService(db),
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
    ..get('/health', _healthHandler)
    ..mount('/auth/', authController.router.call)
    ..mount('/rides/', ridesController.router.call)
    ..mount('/drivers/', driversController.router.call)
    ..mount('/settlement/', settlementController.router.call)
    ..mount('/disputes', disputesController.router.call)
    ..mount('/admin/', adminController.router.call);

  return router.call;
}

Response _healthHandler(Request request) {
  return jsonResponse(200, <String, Object?>{
    'ok': true,
    'service': 'hail-o-backend',
  });
}
