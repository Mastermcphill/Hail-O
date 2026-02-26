import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:hailo_core/core/api/api_client.dart';
import 'package:hailo_core/core/storage/token_storage.dart';
import 'package:hailo_core/features/dispatch/data/dispatch_repository.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

void main() {
  test('dispatch repository maps quote/create/get/status responses', () async {
    final mockClient = MockClient((request) async {
      final path = request.url.path;
      if (request.method == 'POST' && path == '/dispatch/quote') {
        return _jsonResponse(<String, Object?>{
          'ok': true,
          'distance_km': 12.345,
          'duration_min_est': 30,
          'price_minor': 4600,
          'currency': 'NGN',
          'breakdown': <String, Object?>{
            'base_fare_minor': 1000,
            'per_km_minor': 200,
          },
        });
      }
      if (request.method == 'POST' && path == '/dispatch/trips') {
        return _jsonResponse(<String, Object?>{
          'ok': true,
          'trip': _tripPayload(status: 'created'),
        });
      }
      if (request.method == 'GET' && path == '/dispatch/trips/trip_1') {
        return _jsonResponse(<String, Object?>{
          'ok': true,
          'trip': _tripPayload(status: 'created'),
        });
      }
      if (request.method == 'POST' && path == '/dispatch/trips/trip_1/status') {
        return _jsonResponse(<String, Object?>{
          'ok': true,
          'trip': _tripPayload(status: 'searching'),
          'event': <String, Object?>{
            'id': 'evt_1',
            'from_status': 'created',
            'to_status': 'searching',
            'actor_user_id': 'user_1',
            'created_at': '2026-01-01T00:01:00Z',
            'metadata': <String, Object?>{'source': 'test'},
          },
        });
      }
      return http.Response('{"ok":false}', 404);
    });

    final client = ApiClient(
      tokenStorage: const _InMemoryTokenStorage(),
      httpClient: mockClient,
    );
    addTearDown(client.close);
    final repository = DispatchRepository(apiClient: client);

    final quote = await repository.createQuote(
      pickupLat: 6.5,
      pickupLng: 3.3,
      dropoffLat: 6.6,
      dropoffLng: 3.4,
    );
    expect(quote.distanceKm, 12.345);
    expect(quote.priceMinor, 4600);
    expect(quote.currency, 'NGN');

    final created = await repository.createTrip(
      pickupLat: 6.5,
      pickupLng: 3.3,
      dropoffLat: 6.6,
      dropoffLng: 3.4,
      pickupAddress: 'Pickup',
      dropoffAddress: 'Dropoff',
      notes: 'Handle with care',
    );
    expect(created.id, 'trip_1');
    expect(created.status, 'created');

    final fetched = await repository.getTrip('trip_1');
    expect(fetched.id, 'trip_1');
    expect(fetched.pickup.address, 'Pickup');

    final updated = await repository.updateStatus(
      tripId: 'trip_1',
      status: 'searching',
    );
    expect(updated.trip.status, 'searching');
    expect(updated.event.fromStatus, 'created');
    expect(updated.event.toStatus, 'searching');
  });

  test('dispatch repository maps assignment/list/nearby responses', () async {
    final mockClient = MockClient((request) async {
      final path = request.url.path;
      if (request.method == 'POST' && path == '/dispatch/trips/trip_1/assign') {
        return _jsonResponse(<String, Object?>{
          'ok': true,
          'trip': _tripPayload(status: 'assigned'),
          'assignment': <String, Object?>{
            'id': 'asg_1',
            'trip_id': 'trip_1',
            'driver_id': 'driver_1',
            'status': 'assigned',
            'created_at': '2026-01-01T00:02:00Z',
            'updated_at': '2026-01-01T00:02:00Z',
          },
        });
      }
      if (request.method == 'GET' &&
          path == '/dispatch/trips' &&
          request.url.queryParameters['limit'] == '2') {
        return _jsonResponse(<String, Object?>{
          'ok': true,
          'trips': <Map<String, Object?>>[
            _tripPayload(id: 'trip_2', status: 'delivered'),
            _tripPayload(id: 'trip_1', status: 'assigned'),
          ],
          'next_cursor': 'cursor_2',
        });
      }
      if (request.method == 'GET' && path == '/dispatch/drivers/nearby') {
        return _jsonResponse(<String, Object?>{
          'ok': true,
          'drivers': <Map<String, Object?>>[
            <String, Object?>{
              'driver_id': 'driver_1',
              'display_name': 'Ada',
              'status': 'active',
              'safety_score': 95,
              'star_rating': 4.8,
            },
          ],
        });
      }
      return http.Response('{"ok":false}', 404);
    });

    final client = ApiClient(
      tokenStorage: const _InMemoryTokenStorage(),
      httpClient: mockClient,
    );
    addTearDown(client.close);
    final repository = DispatchRepository(apiClient: client);

    final assignment = await repository.assignDriver(
      tripId: 'trip_1',
      driverId: 'driver_1',
    );
    expect(assignment.trip.status, 'assigned');
    expect(assignment.assignment.driverId, 'driver_1');

    final tripsPage = await repository.listTrips(limit: 2);
    expect(tripsPage.trips.length, 2);
    expect(tripsPage.trips.first.id, 'trip_2');
    expect(tripsPage.nextCursor, 'cursor_2');

    final nearby = await repository.listNearbyDrivers(lat: 6.5, lng: 3.3);
    expect(nearby.drivers.length, 1);
    expect(nearby.drivers.first.driverId, 'driver_1');
    expect(nearby.drivers.first.displayName, 'Ada');
  });
}

http.Response _jsonResponse(Map<String, Object?> payload) {
  return http.Response(
    jsonEncode(payload),
    200,
    headers: const <String, String>{'content-type': 'application/json'},
  );
}

Map<String, Object?> _tripPayload({
  String id = 'trip_1',
  required String status,
}) {
  return <String, Object?>{
    'id': id,
    'user_id': 'user_1',
    'status': status,
    'pickup': <String, Object?>{'lat': 6.5, 'lng': 3.3, 'address': 'Pickup'},
    'dropoff': <String, Object?>{'lat': 6.6, 'lng': 3.4, 'address': 'Dropoff'},
    'notes': 'Fragile item',
    'scheduled_at': '2026-01-01T00:00:00Z',
    'created_at': '2026-01-01T00:00:00Z',
    'updated_at': '2026-01-01T00:00:00Z',
  };
}

class _InMemoryTokenStorage extends TokenStorage {
  const _InMemoryTokenStorage();

  @override
  Future<String?> readToken() async => null;
}
