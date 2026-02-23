import '../../../core/api/api_client.dart';
import '../../../core/api/api_config.dart';
import '../models/offer.dart';
import '../models/paywall_copy.dart';
import '../models/seat_selection.dart';
import '../models/timeline_event.dart';
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

MarketplaceRepository createMarketplaceRepository(ApiClient apiClient) {
  if (ApiConfig.mockMode) {
    return MarketplaceRepositoryMock();
  }
  return MarketplaceRepositoryHttp(apiClient: apiClient);
}
