import '../../../core/api/api_client.dart';
import '../../../core/api/api_errors.dart';
import '../models/offer.dart';
import '../models/paywall_copy.dart';
import '../models/purchase_receipt.dart';
import '../models/seat_selection.dart';
import '../models/timeline_event.dart';
import 'marketplace_endpoints.dart';
import 'marketplace_mappers.dart';
import 'marketplace_repository.dart';

class MarketplaceRepositoryHttp implements MarketplaceRepository {
  MarketplaceRepositoryHttp({required ApiClient apiClient})
    : _apiClient = apiClient;

  final ApiClient _apiClient;

  @override
  Future<List<Offer>> fetchOffers() async {
    try {
      final response = await _apiClient.get(MarketplaceEndpoints.offers);
      return mapOffersPayload(extractEnvelopeData(response));
    } catch (error) {
      throw _mapError(
        error,
        fallbackMessage: 'Unable to load marketplace offers right now.',
      );
    }
  }

  @override
  Future<PaywallCopy> fetchPaywallCopy(String offerId) async {
    try {
      final response = await _apiClient.get(
        MarketplaceEndpoints.offerPaywall(offerId),
      );
      return mapPaywallPayload(extractEnvelopeData(response));
    } catch (error) {
      throw _mapError(
        error,
        fallbackMessage: 'Unable to load paywall information for this offer.',
      );
    }
  }

  @override
  Future<String> createCheckout(
    SeatSelection selection, {
    required String idempotencyKey,
  }) async {
    try {
      final response = await _apiClient.post(
        MarketplaceEndpoints.purchases,
        body: selection.toMap(),
        idempotencyKey: idempotencyKey,
      );
      return mapPurchaseIdPayload(extractEnvelopeData(response));
    } on ApiException catch (error) {
      if (error.statusCode == 409) {
        final restored = await restorePurchaseByIdempotencyKey(idempotencyKey);
        if (restored != null && restored.isNotEmpty) {
          return restored;
        }
      }
      throw _mapError(
        error,
        fallbackMessage: 'Unable to create checkout at this time.',
      );
    } catch (error) {
      throw _mapError(
        error,
        fallbackMessage: 'Unable to create checkout at this time.',
      );
    }
  }

  @override
  Future<String?> restorePurchaseByIdempotencyKey(String idempotencyKey) async {
    try {
      final response = await _apiClient.get(
        MarketplaceEndpoints.restorePurchase(idempotencyKey),
      );
      return mapRestoredPurchaseIdPayload(extractEnvelopeData(response));
    } on ApiException catch (error) {
      final code = (error.code ?? '').toLowerCase();
      if (error.statusCode == 404 || code == 'not_implemented') {
        return null;
      }
      throw _mapError(
        error,
        fallbackMessage: 'Unable to restore purchase at this time.',
      );
    } catch (error) {
      throw _mapError(
        error,
        fallbackMessage: 'Unable to restore purchase at this time.',
      );
    }
  }

  @override
  Future<PurchaseReceipt?> fetchPurchaseReceipt(String purchaseId) async {
    try {
      final response = await _apiClient.get(
        MarketplaceEndpoints.purchase(purchaseId),
      );
      return mapPurchaseReceiptPayload(extractEnvelopeData(response));
    } catch (error) {
      throw _mapError(
        error,
        fallbackMessage: 'Unable to load purchase details at this time.',
      );
    }
  }

  @override
  Future<PurchaseReceipt> updateSeatCount({
    required String purchaseId,
    required int seatCount,
  }) async {
    try {
      final response = await _apiClient.patch(
        MarketplaceEndpoints.purchaseSeats(purchaseId),
        body: <String, dynamic>{'seat_count': seatCount},
      );
      return mapPurchaseReceiptPayload(extractEnvelopeData(response));
    } catch (error) {
      throw _mapError(
        error,
        fallbackMessage: 'Unable to update seat count right now.',
      );
    }
  }

  @override
  Future<PurchaseReceipt> updateAssignments({
    required String purchaseId,
    required List<SeatAssignment> assignments,
  }) async {
    try {
      final response = await _apiClient.patch(
        MarketplaceEndpoints.purchaseAssignments(purchaseId),
        body: <String, dynamic>{
          'assignments': assignments
              .map((assignment) => assignment.toMap())
              .toList(growable: false),
        },
      );
      return mapPurchaseReceiptPayload(extractEnvelopeData(response));
    } catch (error) {
      throw _mapError(
        error,
        fallbackMessage: 'Unable to update seat assignments right now.',
      );
    }
  }

  @override
  Future<String> changePlan({
    required String purchaseId,
    required String newOfferId,
  }) async {
    try {
      final response = await _apiClient.post(
        MarketplaceEndpoints.changePlan(purchaseId),
        body: <String, dynamic>{'new_offer_id': newOfferId},
      );
      return mapPurchaseIdPayload(extractEnvelopeData(response));
    } catch (error) {
      throw _mapError(
        error,
        fallbackMessage: 'Unable to change plan right now.',
      );
    }
  }

  @override
  Future<List<TimelineEvent>> fetchTimeline(String purchaseId) async {
    try {
      final response = await _apiClient.get(
        MarketplaceEndpoints.purchaseTimeline(purchaseId),
      );
      return mapTimelinePayload(extractEnvelopeData(response));
    } catch (error) {
      throw _mapError(
        error,
        fallbackMessage: 'Unable to fetch timeline at this time.',
      );
    }
  }
}

MarketplaceRepositoryException _mapError(
  Object error, {
  required String fallbackMessage,
}) {
  if (error is MarketplaceRepositoryException) {
    return error;
  }
  if (error is ApiException) {
    final code = (error.code ?? '').trim().toLowerCase();
    if (error.statusCode == 404 || code == 'not_implemented') {
      return MarketplaceRepositoryException(
        'Marketplace endpoint is not available on this backend yet.',
        code: code.isEmpty ? 'endpoint_not_available' : code,
      );
    }
    final message = error.message.trim().isEmpty
        ? fallbackMessage
        : error.message;
    return MarketplaceRepositoryException(
      message,
      code: error.code ?? 'http_${error.statusCode}',
    );
  }
  return MarketplaceRepositoryException(
    fallbackMessage,
    code: 'unknown_marketplace_error',
  );
}
