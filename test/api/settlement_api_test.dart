import 'package:flutter_test/flutter_test.dart';
import 'package:hail_o_finance_core/data/sqlite/dao/escrow_holds_dao.dart';
import 'package:hail_o_finance_core/data/sqlite/dao/payout_records_dao.dart';
import 'package:hail_o_finance_core/data/sqlite/dao/wallet_ledger_dao.dart';
import 'package:hail_o_finance_core/domain/models/ride_event_type.dart';
import 'package:hail_o_finance_core/domain/models/wallet.dart';
import 'package:hail_o_finance_core/domain/services/ride_orchestrator_service.dart';

import 'api_test_harness.dart';

void main() {
  test(
    'complete ride triggers settlement and writes payout/ledger records',
    () async {
      final harness = await ApiTestHarness.create();
      addTearDown(harness.close);

      final rider = await harness.registerAndLogin(
        role: 'rider',
        email: 'rider.settle@example.com',
        password: 'SuperSecret123',
        registerIdempotencyKey: 'register-rider-settle',
      );
      final driver = await harness.registerAndLogin(
        role: 'driver',
        email: 'driver.settle@example.com',
        password: 'SuperSecret123',
        registerIdempotencyKey: 'register-driver-settle',
      );

      final requestRide = await harness.postJson(
        '/rides/request',
        bearerToken: rider.token,
        idempotencyKey: 'ride-request-settle-1',
        body: <String, Object?>{
          'trip_scope': 'intra_city',
          'scheduled_departure_at': DateTime.now()
              .toUtc()
              .add(const Duration(hours: 1))
              .toIso8601String(),
          'distance_meters': 10000,
          'duration_seconds': 2000,
          'luggage_count': 1,
          'vehicle_class': 'sedan',
          'base_fare_minor': 120000,
          'premium_markup_minor': 20000,
        },
      );
      final requestBody = requestRide.requireJsonMap();
      final rideId = (requestBody['ride_id'] as String?) ?? '';
      final escrowId = (requestBody['escrow_id'] as String?) ?? '';
      expect(rideId, isNotEmpty);
      expect(escrowId, isNotEmpty);

      final accept = await harness.postJson(
        '/rides/$rideId/accept',
        bearerToken: driver.token,
        idempotencyKey: 'ride-accept-settle-1',
        body: const <String, Object?>{},
      );
      expect(accept.statusCode, 200);

      await RideOrchestratorService(harness.db).applyEvent(
        eventType: RideEventType.rideStarted,
        rideId: rideId,
        idempotencyKey: 'ride-started-settle-1',
        payload: const <String, Object?>{},
      );

      await EscrowHoldsDao(harness.db).markReleasedIfHeld(
        escrowId: escrowId,
        releaseMode: 'manual_override',
        releasedAtIso: DateTime.now().toUtc().toIso8601String(),
        idempotencyScope: 'test.release',
        idempotencyKey: 'test.release:$escrowId',
        viaOrchestrator: true,
      );

      final complete = await harness.postJson(
        '/rides/$rideId/complete',
        bearerToken: driver.token,
        idempotencyKey: 'ride-complete-settle-1',
        body: <String, Object?>{'escrow_id': escrowId},
      );
      expect(complete.statusCode, 200);
      final completeBody = complete.requireJsonMap();
      final settlement = completeBody['settlement'] as Map<String, Object?>;
      expect(settlement['ok'], true);

      final payout = await PayoutRecordsDao(
        harness.db,
      ).findByEscrowId(escrowId);
      expect(payout, isNotNull);
      final ledgerRows = await WalletLedgerDao(
        harness.db,
      ).listByWallet(driver.userId, WalletType.driverA);
      expect(ledgerRows.isNotEmpty, true);
    },
  );
}
