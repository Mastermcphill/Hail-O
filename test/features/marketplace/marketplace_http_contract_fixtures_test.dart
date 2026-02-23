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

  test(
    'offers fixture payload maps to List<Offer> with expected contract fields',
    () {
      final envelope = _fixtureMap('offers_ok.json');
      final payload = envelope['data'];
      expect(payload, isA<List<dynamic>>());

      final rawOffers = payload as List<dynamic>;
      expect(rawOffers.length, 3);
      for (final raw in rawOffers) {
        final map = _asMap(raw);
        expect(map['id'], isNotNull);
        expect(map['title'], isNotNull);
        expect(map['subtitle'], isNotNull);
        expect(map['price'], isNotNull);
        expect(map['currency'], isNotNull);
        expect(map['interval'], isNotNull);
        expect(map['perks'], isA<List<dynamic>>());
      }

      final offers = mapOffersPayload(payload);
      expect(offers.length, 3);
      expect(offers.every((offer) => offer.id.isNotEmpty), isTrue);
      expect(offers.every((offer) => offer.title.isNotEmpty), isTrue);
      expect(offers.every((offer) => offer.priceMinor > 0), isTrue);
    },
  );

  test(
    'paywall fixture payload maps to PaywallCopy with non-empty headline and bullets',
    () {
      final envelope = _fixtureMap('paywall_ok.json');
      final payload = envelope['data'];
      final paywall = mapPaywallPayload(payload);

      expect(paywall.offerId, isNotEmpty);
      expect(paywall.headline, isNotEmpty);
      expect(paywall.bullets, isNotEmpty);
    },
  );

  test('purchase fixtures map to receipt and restore contract fields', () {
    final createdEnvelope = _fixtureMap('purchase_created_ok.json');
    final createdPayload = createdEnvelope['data'];
    final createdPayloadMap = _asMap(createdPayload);
    expect(createdPayloadMap['purchaseId'], isNotNull);
    expect(createdPayloadMap['seatCount'], isNotNull);
    expect(createdPayloadMap['totalAmount'], isNotNull);
    expect(createdPayloadMap['currency'], isNotNull);

    final purchaseId = mapPurchaseIdPayload(createdPayload);
    expect(purchaseId, isNotEmpty);

    final restoredEnvelope = _fixtureMap('purchase_restore_ok.json');
    final restoredPayload = restoredEnvelope['data'];
    final restoredId = mapRestoredPurchaseIdPayload(restoredPayload);
    expect(restoredId, purchaseId);

    final purchaseGetEnvelope = _fixtureMap('purchase_get_ok.json');
    final purchaseGetPayload = purchaseGetEnvelope['data'];
    final receipt = mapPurchaseReceiptPayload(purchaseGetPayload);
    expect(receipt.purchaseId, isNotEmpty);
    expect(receipt.seatCount, greaterThan(0));
    expect(receipt.assignments.length, receipt.seatCount);
  });

  test('timeline fixture maps to TimelineEvent list and timestamps parse', () {
    final envelope = _fixtureMap('timeline_ok.json');
    final payload = envelope['data'];
    expect(payload, isA<List<dynamic>>());

    final rawEvents = payload as List<dynamic>;
    final rawTypes = rawEvents
        .map((event) => _asMap(event)['type']?.toString() ?? '')
        .toList(growable: false);
    expect(rawTypes, contains('PLAN_CHANGED'));
    for (final raw in rawEvents) {
      final timestamp = _asMap(raw)['timestamp']?.toString() ?? '';
      expect(DateTime.tryParse(timestamp), isNotNull);
    }

    final events = mapTimelinePayload(payload);
    expect(events, isNotEmpty);
    expect(events.map((event) => event.title), contains('PLAN_CHANGED'));
    expect(
      events.every(
        (event) =>
            event.occurredAt.isUtc ||
            event.occurredAt.isAfter(DateTime.utc(2000)),
      ),
      isTrue,
    );
  });

  test(
    'ApiClient envelope parsing maps error fixtures into controlled ApiException',
    () async {
      final validationResponse = _fixtureRaw('validation_err.json');
      final notImplementedResponse = _fixtureRaw('not_implemented_err.json');
      var callCount = 0;

      final mockClient = MockClient((request) async {
        callCount += 1;
        final raw = callCount == 1
            ? validationResponse
            : notImplementedResponse;
        final status = callCount == 1 ? 400 : 404;
        return http.Response(
          raw,
          status,
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
                contains('Invalid seat count'),
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
                contains('not implemented'),
              ),
        ),
      );
    },
  );

  test(
    'repository http uses fixture envelopes and returns controlled repository errors',
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
        if (request.method == 'PATCH') {
          return _fixtureResponse('validation_err.json', statusCode: 400);
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

      final paywall = await repository.fetchPaywallCopy('offer_sedan_01');
      expect(paywall.headline, isNotEmpty);

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
      expect(restored, purchaseId);

      final receipt = await repository.fetchPurchaseReceipt(purchaseId);
      expect(receipt, isNotNull);
      expect(receipt!.seatCount, 3);

      final timeline = await repository.fetchTimeline(purchaseId);
      expect(timeline.map((event) => event.title), contains('PLAN_CHANGED'));

      await expectLater(
        () => repository.updateSeatCount(purchaseId: purchaseId, seatCount: 0),
        throwsA(
          isA<MarketplaceRepositoryException>()
              .having((error) => error.code, 'code', 'VALIDATION_ERROR')
              .having(
                (error) => error.message,
                'message',
                contains('Invalid seat count'),
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
  return _asMap(decoded);
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

Map<String, dynamic> _asMap(Object? value) {
  if (value is Map<String, dynamic>) {
    return value;
  }
  if (value is Map) {
    return value.map(
      (key, mapValue) => MapEntry<String, dynamic>(key.toString(), mapValue),
    );
  }
  return <String, dynamic>{};
}

class _InMemoryTokenStorage extends TokenStorage {
  const _InMemoryTokenStorage();

  @override
  Future<String?> readToken() async => null;
}
