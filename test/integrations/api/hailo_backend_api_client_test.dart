import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:hail_o_finance_core/integrations/api/api_config.dart';
import 'package:hail_o_finance_core/integrations/api/api_exception.dart';
import 'package:hail_o_finance_core/integrations/api/hailo_backend_api_client.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

void main() {
  group('ApiConfig', () {
    test('defaults to development base URL', () {
      final config = ApiConfig.fromValues();
      expect(config.baseUrl, ApiConfig.defaultDevelopmentBaseUrl);
    });

    test('uses production base URL for production environment', () {
      final config = ApiConfig.fromValues(environment: 'production');
      expect(config.baseUrl, ApiConfig.defaultProductionBaseUrl);
    });

    test('uses explicit base URL override', () {
      final config = ApiConfig.fromValues(baseUrl: 'https://api.example.com/');
      expect(config.baseUrl, 'https://api.example.com');
    });
  });

  group('HailoBackendApiClient', () {
    test('requestRide sends auth, trace and idempotency headers', () async {
      late http.BaseRequest capturedRequest;
      late Map<String, dynamic> capturedBody;

      final client = MockClient((request) async {
        capturedRequest = request;
        final rawBody = request.body;
        capturedBody = jsonDecode(rawBody) as Map<String, dynamic>;
        return http.Response(
          jsonEncode(<String, Object?>{'ride_id': 'ride-1'}),
          201,
          headers: <String, String>{'content-type': 'application/json'},
        );
      });

      final apiClient = HailoBackendApiClient(
        config: const ApiConfig(baseUrl: 'https://api.example.com'),
        httpClient: client,
      );

      final response = await apiClient.requestRide(
        bearerToken: 'jwt-token',
        idempotencyKey: 'idem-1',
        scheduledDepartureAtUtc: DateTime.utc(2026, 2, 15, 12, 0),
        distanceMeters: 15000,
        durationSeconds: 1800,
        luggageCount: 1,
        vehicleClass: 'sedan',
        baseFareMinor: 100000,
        premiumMarkupMinor: 10000,
        connectionFeeMinor: 5000,
        traceId: 'trace-123',
      );

      expect(response['ride_id'], 'ride-1');
      expect(
        capturedRequest.url.toString(),
        'https://api.example.com/rides/request',
      );
      expect(capturedRequest.headers['authorization'], 'Bearer jwt-token');
      expect(capturedRequest.headers['idempotency-key'], 'idem-1');
      expect(capturedRequest.headers['x-trace-id'], 'trace-123');
      expect(capturedBody['base_fare_minor'], 100000);
      expect(
        capturedBody['scheduled_departure_at'],
        '2026-02-15T12:00:00.000Z',
      );
    });

    test('write methods auto-populate trace header when omitted', () async {
      late http.BaseRequest capturedRequest;

      final client = MockClient((request) async {
        capturedRequest = request;
        return http.Response(
          jsonEncode(<String, Object?>{'ok': true}),
          200,
          headers: <String, String>{'content-type': 'application/json'},
        );
      });

      final apiClient = HailoBackendApiClient(
        config: const ApiConfig(baseUrl: 'https://api.example.com'),
        httpClient: client,
      );

      await apiClient.cancelRide(
        bearerToken: 'jwt-token',
        rideId: 'ride-1',
        idempotencyKey: 'idem-2',
      );

      expect((capturedRequest.headers['x-trace-id'] ?? '').isNotEmpty, true);
    });

    test('decodes standard error envelope', () async {
      final client = MockClient((_) async {
        return http.Response(
          jsonEncode(<String, Object?>{
            'code': 'forbidden',
            'message': 'forbidden',
            'trace_id': 'trace-err-1',
          }),
          403,
          headers: <String, String>{'content-type': 'application/json'},
        );
      });

      final apiClient = HailoBackendApiClient(
        config: const ApiConfig(baseUrl: 'https://api.example.com'),
        httpClient: client,
      );

      expect(
        () => apiClient.getRideSnapshot(
          bearerToken: 'bad-token',
          rideId: 'ride-1',
        ),
        throwsA(
          isA<ApiException>()
              .having((error) => error.statusCode, 'statusCode', 403)
              .having((error) => error.code, 'code', 'forbidden')
              .having((error) => error.traceId, 'traceId', 'trace-err-1'),
        ),
      );
    });
  });
}
