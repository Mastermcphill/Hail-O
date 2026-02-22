import 'package:flutter_test/flutter_test.dart';
import 'package:hail_o_finance_core/data/sqlite/dao/penalty_records_dao.dart';

import 'api_test_harness.dart';

void main() {
  test('request ride then accept replay is idempotent', () async {
    final harness = await ApiTestHarness.create();
    addTearDown(harness.close);

    final rider = await harness.registerAndLogin(
      role: 'rider',
      email: 'rider.request@example.com',
      password: 'SuperSecret123',
      registerIdempotencyKey: 'register-rider-request',
    );
    final driver = await harness.registerAndLogin(
      role: 'driver',
      email: 'driver.request@example.com',
      password: 'SuperSecret123',
      registerIdempotencyKey: 'register-driver-request',
    );

    final requestRide = await harness.postJson(
      '/rides/request',
      bearerToken: rider.token,
      idempotencyKey: 'ride-request-1',
      body: <String, Object?>{
        'trip_scope': 'intra_city',
        'scheduled_departure_at': DateTime.now()
            .toUtc()
            .add(const Duration(hours: 2))
            .toIso8601String(),
        'distance_meters': 12000,
        'duration_seconds': 1800,
        'luggage_count': 1,
        'vehicle_class': 'sedan',
        'base_fare_minor': 100000,
        'premium_markup_minor': 10000,
      },
    );
    expect(requestRide.statusCode, 201);
    final requestBody = requestRide.requireJsonMap();
    final rideId = (requestBody['ride_id'] as String?) ?? '';
    expect(rideId, isNotEmpty);

    final accept = await harness.postJson(
      '/rides/$rideId/accept',
      bearerToken: driver.token,
      idempotencyKey: 'ride-accept-1',
      body: const <String, Object?>{},
    );
    expect(accept.statusCode, 200);

    final acceptReplay = await harness.postJson(
      '/rides/$rideId/accept',
      bearerToken: driver.token,
      idempotencyKey: 'ride-accept-1',
      body: const <String, Object?>{},
    );
    expect(acceptReplay.statusCode, 200);
    final replayBody = acceptReplay.requireJsonMap();
    expect(replayBody['replayed'], true);
  });

  test('cancel ride writes penalty record audit', () async {
    final harness = await ApiTestHarness.create();
    addTearDown(harness.close);

    final rider = await harness.registerAndLogin(
      role: 'rider',
      email: 'rider.cancel@example.com',
      password: 'SuperSecret123',
      registerIdempotencyKey: 'register-rider-cancel',
    );

    final requestRide = await harness.postJson(
      '/rides/request',
      bearerToken: rider.token,
      idempotencyKey: 'ride-request-cancel-1',
      body: <String, Object?>{
        'trip_scope': 'intra_city',
        'scheduled_departure_at': DateTime.now()
            .toUtc()
            .add(const Duration(hours: 6))
            .toIso8601String(),
        'distance_meters': 6000,
        'duration_seconds': 1200,
        'luggage_count': 0,
        'vehicle_class': 'sedan',
        'base_fare_minor': 80000,
        'premium_markup_minor': 0,
      },
    );
    final rideId = (requestRide.requireJsonMap()['ride_id'] as String?) ?? '';

    final cancel = await harness.postJson(
      '/rides/$rideId/cancel',
      bearerToken: rider.token,
      idempotencyKey: 'ride-cancel-1',
      body: const <String, Object?>{},
    );
    expect(cancel.statusCode, 200);

    final records = await PenaltyRecordsDao(harness.db).listByRideId(rideId);
    expect(records, hasLength(1));
    expect(records.first.rideId, rideId);
    expect(records.first.idempotencyScope, 'cancellation_penalty');
  });
}
