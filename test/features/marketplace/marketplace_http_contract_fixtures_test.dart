import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:hailo_core/core/api/api_client.dart';
import 'package:hailo_core/core/api/api_errors.dart';
import 'package:hailo_core/core/storage/token_storage.dart';
import 'package:hailo_core/features/marketplace/data/marketplace_mappers.dart';
import 'package:hailo_core/features/marketplace/data/marketplace_repository.dart';
import 'package:hailo_core/features/marketplace/data/marketplace_repository_http.dart';
import 'package:hailo_core/features/marketplace/models/seat_selection.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('success fixtures map into marketplace models through mappers', () {
    final offersFixture = _fixtureMap('offers_ok.json');
    final paywallFixture = _fixtureMap('paywall_ok.json');
    final purchaseCreatedFixture = _fixtureMap('purchase_created_ok.json');
    final purchaseRestoreFixture = _fixtureMap('purchase_restore_ok.json');
    final purchaseGetFixture = _fixtureMap('purchase_get_ok.json');
    final timelineFixture = _fixtureMap('timeline_ok.json');

    final offers = mapOffersFromEnvelope(offersFixture);
    expect(offers.length, 3);
    expect(offers.first.id, isNotEmpty);
    expect(offers.first.title, isNotEmpty);
    expect(offers.first.highlights, isNotEmpty);

    final paywall = mapPaywallFromEnvelope(paywallFixture);
    expect(paywall.offerId, 'offer_sedan_01');
    expect(paywall.headline, isNotEmpty);
    expect(paywall.connectionFeeMinor, greaterThan(0));

    final purchaseId = mapPurchaseIdFromEnvelope(purchaseCreatedFixture);
    expect(purchaseId, 'purchase_created_001');

    final restoredId = mapRestoredPurchaseIdFromEnvelope(
      purchaseRestoreFixture,
    );
    expect(restoredId, 'purchase_created_001');

    final receipt = mapPurchaseReceiptFromEnvelope(purchaseGetFixture);
    expect(receipt.purchaseId, isNotEmpty);
    expect(receipt.offerId, isNotEmpty);
    expect(receipt.seatCount, greaterThan(0));
    expect(receipt.assignments, isNotEmpty);

    final timeline = mapTimelineFromEnvelope(timelineFixture);
    expect(timeline, isNotEmpty);
    expect(
      timeline.map((event) => event.title).toSet(),
      containsAll(<String>[
        'PURCHASE_CREATED',
        'SEATS_SELECTED',
        'SEATS_UPDATED',
        'ASSIGNMENT_UPDATED',
        'PLAN_CHANGED',
      ]),
    );
  });

  test(
    'repository http parses enveloped success fixtures end-to-end',
    () async {
      final mockClient = MockClient((request) async {
        final path = request.url.path;
        if (request.method == 'GET' && path == '/marketplace/offers') {
          return _fixtureResponse('offers_ok.json', statusCode: 200);
        }
        if (request.method == 'GET' &&
            path == '/marketplace/offers/offer_sedan_01/paywall') {
          return _fixtureResponse('paywall_ok.json', statusCode: 200);
        }
        if (request.method == 'POST' && path == '/marketplace/purchases') {
          return _fixtureResponse('purchase_created_ok.json', statusCode: 200);
        }
        if (request.method == 'GET' &&
            path == '/marketplace/purchases/restore') {
          return _fixtureResponse('purchase_restore_ok.json', statusCode: 200);
        }
        if (request.method == 'GET' &&
            path == '/marketplace/purchases/purchase_created_001') {
          return _fixtureResponse('purchase_get_ok.json', statusCode: 200);
        }
        if (request.method == 'GET' &&
            path == '/marketplace/purchases/purchase_created_001/timeline') {
          return _fixtureResponse('timeline_ok.json', statusCode: 200);
        }
        return _fixtureResponse('not_implemented_err.json', statusCode: 404);
      });

      final apiClient = ApiClient(
        tokenStorage: const _InMemoryTokenStorage(),
        httpClient: mockClient,
      );
      addTearDown(apiClient.close);

      final repository = MarketplaceRepositoryHttp(apiClient: apiClient);

      final offers = await repository.fetchOffers();
      expect(offers.length, 3);
      expect(offers.first.id, 'offer_sedan_01');

      final paywall = await repository.fetchPaywallCopy('offer_sedan_01');
      expect(paywall.offerId, 'offer_sedan_01');
      expect(paywall.ctaLabel, isNotEmpty);

      final purchaseId = await repository.createCheckout(
        const SeatSelection(
          offerId: 'offer_sedan_01',
          seatCount: 2,
          assignments: <SeatAssignment>[
            SeatAssignment(seatNumber: 1, name: 'Ada', email: 'ada@test.dev'),
            SeatAssignment(
              seatNumber: 2,
              name: 'Kunle',
              email: 'kunle@test.dev',
            ),
          ],
        ),
        idempotencyKey: 'idem_fixture',
      );
      expect(purchaseId, 'purchase_created_001');

      final restored = await repository.restorePurchaseByIdempotencyKey(
        'idem_fixture',
      );
      expect(restored, 'purchase_created_001');

      final receipt = await repository.fetchPurchaseReceipt(
        'purchase_created_001',
      );
      expect(receipt, isNotNull);
      expect(receipt!.status, isNotEmpty);

      final timeline = await repository.fetchTimeline('purchase_created_001');
      expect(timeline.length, 5);
    },
  );

  test(
    'api client parses enveloped error fixtures into controlled ApiException',
    () async {
      final validationResponse = _fixtureRaw('validation_err.json');
      final notImplementedResponse = _fixtureRaw('not_implemented_err.json');
      var callIndex = 0;

      final mockClient = MockClient((request) async {
        callIndex += 1;
        if (callIndex == 1) {
          return http.Response(
            validationResponse,
            400,
            headers: const <String, String>{'content-type': 'application/json'},
          );
        }
        return http.Response(
          notImplementedResponse,
          404,
          headers: const <String, String>{'content-type': 'application/json'},
        );
      });

      final apiClient = ApiClient(
        tokenStorage: const _InMemoryTokenStorage(),
        httpClient: mockClient,
      );
      addTearDown(apiClient.close);

      await expectLater(
        () => apiClient.post(
          '/marketplace/purchases',
          body: const <String, dynamic>{},
        ),
        throwsA(
          isA<ApiException>()
              .having((error) => error.code, 'code', 'VALIDATION_ERROR')
              .having(
                (error) => error.message,
                'message',
                contains('Invalid seat count supplied.'),
              ),
        ),
      );

      await expectLater(
        () => apiClient.get('/marketplace/offers'),
        throwsA(
          isA<ApiException>()
              .having((error) => error.code, 'code', 'NOT_IMPLEMENTED')
              .having(
                (error) => error.message,
                'message',
                contains('not implemented yet'),
              ),
        ),
      );
    },
  );

  test(
    'repository surfaces controlled MarketplaceRepositoryException on envelope errors',
    () async {
      final mockClient = MockClient((request) async {
        if (request.method == 'GET') {
          return _fixtureResponse('not_implemented_err.json', statusCode: 404);
        }
        return _fixtureResponse('validation_err.json', statusCode: 400);
      });

      final apiClient = ApiClient(
        tokenStorage: const _InMemoryTokenStorage(),
        httpClient: mockClient,
      );
      addTearDown(apiClient.close);

      final repository = MarketplaceRepositoryHttp(apiClient: apiClient);

      await expectLater(
        () => repository.fetchOffers(),
        throwsA(
          isA<MarketplaceRepositoryException>().having(
            (error) => error.code,
            'code',
            'not_implemented',
          ),
        ),
      );

      await expectLater(
        () => repository.createCheckout(
          const SeatSelection(
            offerId: 'offer_sedan_01',
            seatCount: 0,
            assignments: <SeatAssignment>[],
          ),
          idempotencyKey: 'idem_invalid',
        ),
        throwsA(
          isA<MarketplaceRepositoryException>()
              .having((error) => error.code, 'code', 'VALIDATION_ERROR')
              .having(
                (error) => error.message,
                'message',
                contains('Invalid seat count supplied.'),
              ),
        ),
      );
    },
  );
}

Map<String, dynamic> _fixtureMap(String fileName) {
  final file = File('test/fixtures/marketplace/$fileName');
  final raw = file.readAsStringSync();
  final decoded = jsonDecode(raw);
  return (decoded as Map).map(
    (key, value) => MapEntry<String, dynamic>(key.toString(), value),
  );
}

String _fixtureRaw(String fileName) {
  final file = File('test/fixtures/marketplace/$fileName');
  return file.readAsStringSync();
}

http.Response _fixtureResponse(String fileName, {required int statusCode}) {
  return http.Response(
    _fixtureRaw(fileName),
    statusCode,
    headers: const <String, String>{'content-type': 'application/json'},
  );
}

class _InMemoryTokenStorage extends TokenStorage {
  const _InMemoryTokenStorage();

  @override
  Future<String?> readToken() async => null;
}
