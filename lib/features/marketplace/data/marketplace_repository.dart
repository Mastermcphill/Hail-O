import '../../../core/api/api_client.dart';
import '../../../core/api/api_config.dart';
import '../models/offer.dart';
import '../models/paywall_copy.dart';
import '../models/purchase_receipt.dart';
import '../models/seat_selection.dart';
import '../models/timeline_event.dart';
import 'marketplace_dev_settings.dart';
import 'marketplace_repository_http.dart';
import 'marketplace_repository_mock.dart';

abstract class MarketplaceRepository {
  Future<List<Offer>> fetchOffers();

  Future<PaywallCopy> fetchPaywallCopy(String offerId);

  Future<String> createCheckout(
    SeatSelection selection, {
    required String idempotencyKey,
  });

  Future<String?> restorePurchaseByIdempotencyKey(String idempotencyKey);

  Future<PurchaseReceipt?> fetchPurchaseReceipt(String purchaseId);

  Future<PurchaseReceipt> updateSeatCount({
    required String purchaseId,
    required int seatCount,
  });

  Future<PurchaseReceipt> updateAssignments({
    required String purchaseId,
    required List<SeatAssignment> assignments,
  });

  Future<String> changePlan({
    required String purchaseId,
    required String newOfferId,
  });

  Future<List<TimelineEvent>> fetchTimeline(String purchaseId);
}

class MarketplaceRepositoryException implements Exception {
  const MarketplaceRepositoryException(this.message, {this.code});

  final String message;
  final String? code;

  @override
  String toString() {
    if (code == null || code!.isEmpty) {
      return message;
    }
    return '$code: $message';
  }
}

class MarketplaceRepositorySwitching implements MarketplaceRepository {
  MarketplaceRepositorySwitching({
    required MarketplaceRepository httpRepository,
    required MarketplaceRepository mockRepository,
    required MarketplaceDevSettings devSettings,
    required bool mockMode,
  }) : _httpRepository = httpRepository,
       _mockRepository = mockRepository,
       _devSettings = devSettings,
       _mockMode = mockMode;

  final MarketplaceRepository _httpRepository;
  final MarketplaceRepository _mockRepository;
  final MarketplaceDevSettings _devSettings;
  final bool _mockMode;

  @override
  Future<List<Offer>> fetchOffers() {
    return _execute(
      httpCall: _httpRepository.fetchOffers,
      mockCall: _mockRepository.fetchOffers,
    );
  }

  @override
  Future<PaywallCopy> fetchPaywallCopy(String offerId) {
    return _execute(
      httpCall: () => _httpRepository.fetchPaywallCopy(offerId),
      mockCall: () => _mockRepository.fetchPaywallCopy(offerId),
    );
  }

  @override
  Future<String> createCheckout(
    SeatSelection selection, {
    required String idempotencyKey,
  }) {
    return _execute(
      httpCall: () => _httpRepository.createCheckout(
        selection,
        idempotencyKey: idempotencyKey,
      ),
      mockCall: () => _mockRepository.createCheckout(
        selection,
        idempotencyKey: idempotencyKey,
      ),
    );
  }

  @override
  Future<String?> restorePurchaseByIdempotencyKey(String idempotencyKey) {
    return _execute(
      httpCall: () =>
          _httpRepository.restorePurchaseByIdempotencyKey(idempotencyKey),
      mockCall: () =>
          _mockRepository.restorePurchaseByIdempotencyKey(idempotencyKey),
    );
  }

  @override
  Future<PurchaseReceipt?> fetchPurchaseReceipt(String purchaseId) {
    return _execute(
      httpCall: () => _httpRepository.fetchPurchaseReceipt(purchaseId),
      mockCall: () => _mockRepository.fetchPurchaseReceipt(purchaseId),
    );
  }

  @override
  Future<PurchaseReceipt> updateSeatCount({
    required String purchaseId,
    required int seatCount,
  }) {
    return _execute(
      httpCall: () => _httpRepository.updateSeatCount(
        purchaseId: purchaseId,
        seatCount: seatCount,
      ),
      mockCall: () => _mockRepository.updateSeatCount(
        purchaseId: purchaseId,
        seatCount: seatCount,
      ),
    );
  }

  @override
  Future<PurchaseReceipt> updateAssignments({
    required String purchaseId,
    required List<SeatAssignment> assignments,
  }) {
    return _execute(
      httpCall: () => _httpRepository.updateAssignments(
        purchaseId: purchaseId,
        assignments: assignments,
      ),
      mockCall: () => _mockRepository.updateAssignments(
        purchaseId: purchaseId,
        assignments: assignments,
      ),
    );
  }

  @override
  Future<String> changePlan({
    required String purchaseId,
    required String newOfferId,
  }) {
    return _execute(
      httpCall: () => _httpRepository.changePlan(
        purchaseId: purchaseId,
        newOfferId: newOfferId,
      ),
      mockCall: () => _mockRepository.changePlan(
        purchaseId: purchaseId,
        newOfferId: newOfferId,
      ),
    );
  }

  @override
  Future<List<TimelineEvent>> fetchTimeline(String purchaseId) {
    return _execute(
      httpCall: () => _httpRepository.fetchTimeline(purchaseId),
      mockCall: () => _mockRepository.fetchTimeline(purchaseId),
    );
  }

  Future<T> _execute<T>({
    required Future<T> Function() httpCall,
    required Future<T> Function() mockCall,
  }) async {
    if (!_mockMode) {
      return httpCall();
    }

    final preferHttp = await _devSettings.readUseLiveApi();
    if (!preferHttp) {
      return mockCall();
    }

    try {
      return await httpCall();
    } on MarketplaceRepositoryException catch (error) {
      if (_isMockFallbackError(error)) {
        return mockCall();
      }
      rethrow;
    }
  }

  bool _isMockFallbackError(MarketplaceRepositoryException error) {
    final code = (error.code ?? '').trim().toLowerCase();
    return code == 'endpoint_not_available' ||
        code == 'not_implemented' ||
        code == 'http_404';
  }
}

MarketplaceRepository createMarketplaceRepository(
  ApiClient apiClient, {
  MarketplaceRepository? httpRepository,
  MarketplaceRepository? mockRepository,
  MarketplaceDevSettings? devSettings,
  bool? mockModeOverride,
}) {
  final resolvedMockMode = mockModeOverride ?? ApiConfig.mockMode;
  return MarketplaceRepositorySwitching(
    httpRepository:
        httpRepository ?? MarketplaceRepositoryHttp(apiClient: apiClient),
    mockRepository: mockRepository ?? MarketplaceRepositoryMock(),
    devSettings: devSettings ?? const MarketplaceDevSettings(),
    mockMode: resolvedMockMode,
  );
}

MarketplaceRepository createMarketplaceRepositoryForTesting({
  required MarketplaceRepository httpRepository,
  required MarketplaceRepository mockRepository,
  required MarketplaceDevSettings devSettings,
  required bool mockMode,
}) {
  return MarketplaceRepositorySwitching(
    httpRepository: httpRepository,
    mockRepository: mockRepository,
    devSettings: devSettings,
    mockMode: mockMode,
  );
}
