import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:hailo_core/core/api/api_client.dart';
import 'package:hailo_core/core/storage/token_storage.dart';
import 'package:hailo_core/features/marketplace/data/marketplace_local_store.dart';
import 'package:hailo_core/features/marketplace/data/marketplace_repository_http.dart';
import 'package:hailo_core/features/marketplace/data/marketplace_repository_mock.dart';
import 'package:hailo_core/features/marketplace/models/seat_selection.dart';
import 'package:hailo_core/features/marketplace/state/marketplace_controller.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues(<String, Object>{});
  });

  test(
    'same selection reuses idempotency key and returns the same purchase id',
    () async {
      final repository = MarketplaceRepositoryMock();
      final controller = MarketplaceController(repository: repository);
      await controller.loadOffers();
      final offerId = controller.offers.first.id;

      controller.setSeatCount(2);
      controller.updateAssignmentName(0, 'Ada');
      controller.updateAssignmentEmail(0, 'ada@test.dev');
      controller.updateAssignmentName(1, 'Kunle');
      controller.updateAssignmentEmail(1, 'kunle@test.dev');

      final firstPurchaseId = await controller.createCheckout(offerId: offerId);
      expect(firstPurchaseId, isNotNull);
      expect(firstPurchaseId, isNotEmpty);

      final signature = _selectionSignature(
        offerId: offerId,
        seatCount: 2,
        assignments: const <SeatAssignment>[
          SeatAssignment(seatNumber: 1, name: 'Ada', email: 'ada@test.dev'),
          SeatAssignment(seatNumber: 2, name: 'Kunle', email: 'kunle@test.dev'),
        ],
      );
      const localStore = MarketplaceLocalStore();
      final firstKey = await localStore.readCheckoutIdempotencyKey(signature);
      expect(firstKey, isNotNull);
      expect(firstKey, isNotEmpty);

      final secondPurchaseId = await controller.createCheckout(
        offerId: offerId,
      );
      final secondKey = await localStore.readCheckoutIdempotencyKey(signature);

      expect(secondPurchaseId, firstPurchaseId);
      expect(secondKey, firstKey);
    },
  );

  test('failed create can be resumed via persisted idempotency key', () async {
    final repository = MarketplaceRepositoryMock(
      failFirstCreateCheckout: true,
      delayFirstRestore: true,
    );
    final controller = MarketplaceController(repository: repository);
    await controller.loadOffers();
    final offerId = controller.offers.first.id;

    final firstAttempt = await controller.createCheckout(offerId: offerId);
    expect(firstAttempt, isNull);
    expect(controller.pendingCheckoutIdempotencyKey, isNotNull);

    final resumed = await controller.resumePendingCheckout(offerId: offerId);
    expect(resumed, isNotNull);
    expect(resumed, isNotEmpty);
  });

  test('api client retries 500 twice before succeeding', () async {
    var attempts = 0;
    final httpClient = MockClient((request) async {
      attempts += 1;
      if (attempts < 3) {
        return _jsonResponse(
          status: 500,
          body: <String, dynamic>{
            'ok': false,
            'code': 'temporary_error',
            'message': 'try again',
          },
        );
      }
      return _jsonResponse(
        status: 200,
        body: <String, dynamic>{'ok': true, 'purchase_id': 'purchase_retry_ok'},
      );
    });

    final apiClient = ApiClient(
      tokenStorage: const _InMemoryTokenStorage(),
      httpClient: httpClient,
    );
    addTearDown(apiClient.close);

    final response = await apiClient.post(
      '/marketplace/purchases',
      body: <String, dynamic>{'offer_id': 'http_offer_1', 'seat_count': 1},
      idempotencyKey: 'idem_retry_test',
    );

    expect(attempts, 3);
    expect(response['purchase_id'], 'purchase_retry_ok');
  });

  test('409 checkout conflict is resolved by restore lookup', () async {
    var restoreCalled = false;
    final httpClient = MockClient((request) async {
      final path = request.url.path;
      if (request.method == 'POST' && path == '/marketplace/purchases') {
        return _jsonResponse(
          status: 409,
          body: <String, dynamic>{
            'ok': false,
            'code': 'conflict',
            'message': 'already exists',
          },
        );
      }
      if (request.method == 'GET' && path == '/marketplace/purchases/restore') {
        restoreCalled = true;
        return _jsonResponse(
          status: 200,
          body: <String, dynamic>{
            'ok': true,
            'purchase_id': 'purchase_restored_conflict',
          },
        );
      }
      return _jsonResponse(
        status: 404,
        body: <String, dynamic>{
          'ok': false,
          'code': 'not_found',
          'message': 'missing',
        },
      );
    });

    final apiClient = ApiClient(
      tokenStorage: const _InMemoryTokenStorage(),
      httpClient: httpClient,
    );
    addTearDown(apiClient.close);
    final repository = MarketplaceRepositoryHttp(apiClient: apiClient);

    final purchaseId = await repository.createCheckout(
      const SeatSelection(
        offerId: 'offer_http',
        seatCount: 1,
        assignments: <SeatAssignment>[
          SeatAssignment(seatNumber: 1, name: 'A', email: 'a@test.dev'),
        ],
      ),
      idempotencyKey: 'idem_conflict_case',
    );

    expect(restoreCalled, isTrue);
    expect(purchaseId, 'purchase_restored_conflict');
  });
}

String _selectionSignature({
  required String offerId,
  required int seatCount,
  required List<SeatAssignment> assignments,
}) {
  return jsonEncode(<String, dynamic>{
    'offer_id': offerId,
    'seat_count': seatCount,
    'assignments': assignments
        .map(
          (assignment) => <String, dynamic>{
            'seat_number': assignment.seatNumber,
            'name': assignment.name,
            'email': assignment.email,
          },
        )
        .toList(growable: false),
  });
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
