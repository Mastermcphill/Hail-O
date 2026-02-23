import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:hailo_core/core/api/api_client.dart';
import 'package:hailo_core/core/storage/token_storage.dart';
import 'package:hailo_core/features/marketplace/data/marketplace_dev_settings.dart';
import 'package:hailo_core/features/marketplace/data/marketplace_repository.dart';
import 'package:hailo_core/features/marketplace/data/marketplace_repository_http.dart';
import 'package:hailo_core/features/marketplace/data/marketplace_repository_mock.dart';
import 'package:hailo_core/features/marketplace/models/seat_selection.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues(<String, Object>{});
  });

  test(
    'live-api toggle prefers HTTP path and sends idempotency header',
    () async {
      SharedPreferences.setMockInitialValues(<String, Object>{
        MarketplaceDevSettings.useLiveApiPreferenceKey: true,
      });

      final requestLog = <String>[];
      final mockClient = MockClient((request) async {
        requestLog.add('${request.method} ${request.url.path}');

        if (request.method == 'GET' &&
            request.url.path == '/marketplace/offers') {
          return _jsonResponse(
            status: 200,
            body: <String, dynamic>{
              'ok': true,
              'offers': <Map<String, dynamic>>[
                <String, dynamic>{
                  'id': 'http_offer_live',
                  'title': 'HTTP Offer',
                  'vehicle_class': 'sedan',
                  'price_minor': 3000,
                  'rating': 4.7,
                  'seats_available': 4,
                  'eta_minutes': 5,
                  'highlights': <String>['http'],
                },
              ],
            },
          );
        }

        if (request.method == 'POST' &&
            request.url.path == '/marketplace/purchases') {
          expect(
            request.headers.entries.any(
              (entry) =>
                  entry.key.toLowerCase() == 'idempotency-key' &&
                  entry.value == 'idem_live_header',
            ),
            isTrue,
          );
          return _jsonResponse(
            status: 200,
            body: <String, dynamic>{
              'ok': true,
              'purchase_id': 'purchase_live_http',
            },
          );
        }

        return _jsonResponse(
          status: 404,
          body: <String, dynamic>{'ok': false, 'message': 'not found'},
        );
      });

      final apiClient = ApiClient(
        tokenStorage: const _InMemoryTokenStorage(),
        httpClient: mockClient,
      );
      addTearDown(apiClient.close);

      final repository = createMarketplaceRepositoryForTesting(
        httpRepository: MarketplaceRepositoryHttp(apiClient: apiClient),
        mockRepository: MarketplaceRepositoryMock(),
        devSettings: const MarketplaceDevSettings(),
        mockMode: true,
      );

      final offers = await repository.fetchOffers();
      expect(offers.first.id, 'http_offer_live');

      final purchaseId = await repository.createCheckout(
        const SeatSelection(
          offerId: 'http_offer_live',
          seatCount: 1,
          assignments: <SeatAssignment>[
            SeatAssignment(seatNumber: 1, name: 'Ada', email: 'ada@test.dev'),
          ],
        ),
        idempotencyKey: 'idem_live_header',
      );

      expect(purchaseId, 'purchase_live_http');
      expect(requestLog, contains('GET /marketplace/offers'));
      expect(requestLog, contains('POST /marketplace/purchases'));
    },
  );

  test(
    'HTTP 404 falls back to mock repository when mock mode is enabled',
    () async {
      SharedPreferences.setMockInitialValues(<String, Object>{
        MarketplaceDevSettings.useLiveApiPreferenceKey: true,
      });

      var httpAttempts = 0;
      final mockClient = MockClient((request) async {
        httpAttempts += 1;
        return _jsonResponse(
          status: 404,
          body: <String, dynamic>{'ok': false, 'message': 'missing'},
        );
      });

      final apiClient = ApiClient(
        tokenStorage: const _InMemoryTokenStorage(),
        httpClient: mockClient,
      );
      addTearDown(apiClient.close);

      final repository = createMarketplaceRepositoryForTesting(
        httpRepository: MarketplaceRepositoryHttp(apiClient: apiClient),
        mockRepository: MarketplaceRepositoryMock(),
        devSettings: const MarketplaceDevSettings(),
        mockMode: true,
      );

      final offers = await repository.fetchOffers();
      expect(httpAttempts, greaterThan(0));
      expect(offers, isNotEmpty);
      expect(offers.first.id, 'offer_sedan_01');
    },
  );

  test(
    'with mockMode disabled, marketplace 404 surfaces a controlled repository error',
    () async {
      SharedPreferences.setMockInitialValues(<String, Object>{
        MarketplaceDevSettings.useLiveApiPreferenceKey: true,
      });

      final mockClient = MockClient((request) async {
        return _jsonResponse(
          status: 404,
          body: <String, dynamic>{'ok': false, 'message': 'missing endpoint'},
        );
      });

      final apiClient = ApiClient(
        tokenStorage: const _InMemoryTokenStorage(),
        httpClient: mockClient,
      );
      addTearDown(apiClient.close);

      final repository = createMarketplaceRepositoryForTesting(
        httpRepository: MarketplaceRepositoryHttp(apiClient: apiClient),
        mockRepository: MarketplaceRepositoryMock(),
        devSettings: const MarketplaceDevSettings(),
        mockMode: false,
      );

      await expectLater(
        repository.fetchOffers(),
        throwsA(isA<MarketplaceRepositoryException>()),
      );
    },
  );
}

http.Response _jsonResponse({
  required int status,
  required Map<String, dynamic> body,
}) {
  return http.Response(
    jsonEncode(body),
    status,
    headers: const <String, String>{'content-type': 'application/json'},
  );
}

class _InMemoryTokenStorage extends TokenStorage {
  const _InMemoryTokenStorage();

  @override
  Future<String?> readToken() async => null;
}
