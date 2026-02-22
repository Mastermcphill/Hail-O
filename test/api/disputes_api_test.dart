import 'package:flutter_test/flutter_test.dart';
import 'package:hail_o_finance_core/data/sqlite/dao/escrow_holds_dao.dart';
import 'package:hail_o_finance_core/domain/models/ride_event_type.dart';
import 'package:hail_o_finance_core/domain/services/ride_orchestrator_service.dart';

import 'api_test_harness.dart';

void main() {
  test('open and resolve dispute through API', () async {
    final harness = await ApiTestHarness.create();
    addTearDown(harness.close);

    final rider = await harness.registerAndLogin(
      role: 'rider',
      email: 'rider.dispute@example.com',
      password: 'SuperSecret123',
      registerIdempotencyKey: 'register-rider-dispute',
    );
    final driver = await harness.registerAndLogin(
      role: 'driver',
      email: 'driver.dispute@example.com',
      password: 'SuperSecret123',
      registerIdempotencyKey: 'register-driver-dispute',
    );
    final admin = await harness.registerAndLogin(
      role: 'admin',
      email: 'admin.dispute@example.com',
      password: 'SuperSecret123',
      registerIdempotencyKey: 'register-admin-dispute',
    );

    final requestRide = await harness.postJson(
      '/rides/request',
      bearerToken: rider.token,
      idempotencyKey: 'ride-request-dispute-1',
      body: <String, Object?>{
        'trip_scope': 'intra_city',
        'scheduled_departure_at': DateTime.now()
            .toUtc()
            .add(const Duration(hours: 1))
            .toIso8601String(),
        'distance_meters': 9000,
        'duration_seconds': 1800,
        'luggage_count': 0,
        'vehicle_class': 'sedan',
        'base_fare_minor': 100000,
        'premium_markup_minor': 0,
      },
    );
    final requestBody = requestRide.requireJsonMap();
    final rideId = (requestBody['ride_id'] as String?) ?? '';
    final escrowId = (requestBody['escrow_id'] as String?) ?? '';

    await harness.postJson(
      '/rides/$rideId/accept',
      bearerToken: driver.token,
      idempotencyKey: 'ride-accept-dispute-1',
      body: const <String, Object?>{},
    );
    await RideOrchestratorService(harness.db).applyEvent(
      eventType: RideEventType.rideStarted,
      rideId: rideId,
      idempotencyKey: 'ride-start-dispute-1',
      payload: const <String, Object?>{},
    );
    await EscrowHoldsDao(harness.db).markReleasedIfHeld(
      escrowId: escrowId,
      releaseMode: 'manual_override',
      releasedAtIso: DateTime.now().toUtc().toIso8601String(),
      idempotencyScope: 'test.release.dispute',
      idempotencyKey: 'test.release.dispute:$escrowId',
      viaOrchestrator: true,
    );
    await harness.postJson(
      '/rides/$rideId/complete',
      bearerToken: driver.token,
      idempotencyKey: 'ride-complete-dispute-1',
      body: <String, Object?>{'escrow_id': escrowId},
    );

    final open = await harness.postJson(
      '/disputes',
      bearerToken: rider.token,
      idempotencyKey: 'dispute-open-1',
      body: <String, Object?>{'ride_id': rideId, 'reason': 'driver late'},
    );
    expect(open.statusCode, 201);
    final disputeId = (open.requireJsonMap()['dispute_id'] as String?) ?? '';
    expect(disputeId, isNotEmpty);

    final resolve = await harness.postJson(
      '/disputes/$disputeId/resolve',
      bearerToken: admin.token,
      idempotencyKey: 'dispute-resolve-1',
      body: <String, Object?>{'refund_minor': 5000},
    );
    expect(resolve.statusCode, 200);
    final resolveBody = resolve.requireJsonMap();
    expect(resolveBody['status'], 'resolved');
  });
}
