import '../../../core/api/api_client.dart';
import '../../../core/api/api_errors.dart';
import '../models/billing_invoice.dart';
import '../models/offer.dart';
import '../models/org_summary.dart';
import '../models/paywall_copy.dart';
import '../models/pricing_breakdown.dart';
import '../models/purchase_receipt.dart';
import '../models/purchase_snapshot.dart';
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
  Future<PricingBreakdown> fetchPricingPreview({
    required String orgId,
    required String offerId,
    required int seats,
  }) async {
    try {
      final response = await _apiClient.get(
        MarketplaceEndpoints.pricingPreview(
          orgId: orgId,
          offerId: offerId,
          seats: seats,
        ),
      );
      return mapPricingBreakdownPayload(extractEnvelopeData(response));
    } catch (error) {
      throw _mapError(
        error,
        fallbackMessage: 'Unable to load pricing preview right now.',
      );
    }
  }

  @override
  Future<PricingBreakdown> applyCoupon({
    required String orgId,
    required String couponCode,
    required String offerId,
    required int seats,
  }) async {
    try {
      final response = await _apiClient.post(
        MarketplaceEndpoints.applyCoupon,
        body: <String, dynamic>{
          'org_id': orgId,
          'coupon_code': couponCode,
          'offer_id': offerId,
          'seats': seats,
        },
      );
      return mapPricingBreakdownPayload(extractEnvelopeData(response));
    } catch (error) {
      throw _mapError(
        error,
        fallbackMessage: 'Unable to apply coupon at this time.',
      );
    }
  }

  @override
  Future<PricingBreakdown> removeCoupon({
    required String orgId,
    required String offerId,
    required int seats,
  }) async {
    try {
      final response = await _apiClient.delete(
        MarketplaceEndpoints.removeCoupon,
        body: <String, dynamic>{
          'org_id': orgId,
          'offer_id': offerId,
          'seats': seats,
        },
      );
      return mapPricingBreakdownPayload(extractEnvelopeData(response));
    } catch (error) {
      throw _mapError(
        error,
        fallbackMessage: 'Unable to remove coupon at this time.',
      );
    }
  }

  @override
  Future<PricingBreakdown> applyReferral({
    required String orgId,
    required String referralCode,
    required String offerId,
    required int seats,
  }) async {
    try {
      final response = await _apiClient.post(
        MarketplaceEndpoints.applyReferral,
        body: <String, dynamic>{
          'org_id': orgId,
          'referral_code': referralCode,
          'offer_id': offerId,
          'seats': seats,
        },
      );
      return mapPricingBreakdownPayload(extractEnvelopeData(response));
    } catch (error) {
      throw _mapError(
        error,
        fallbackMessage: 'Unable to apply referral code at this time.',
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

  @override
  Future<List<BillingInvoice>> fetchInvoices(String orgId) async {
    try {
      final response = await _apiClient.get(
        MarketplaceEndpoints.orgInvoices(orgId),
      );
      return mapInvoiceListPayload(extractEnvelopeData(response));
    } catch (error) {
      throw _mapError(
        error,
        fallbackMessage: 'Unable to load billing invoices at this time.',
      );
    }
  }

  @override
  Future<BillingInvoice?> retryInvoice({
    required String orgId,
    required String invoiceId,
  }) async {
    try {
      final response = await _apiClient.post(
        MarketplaceEndpoints.orgRetryInvoice(orgId, invoiceId),
        body: const <String, dynamic>{},
      );
      return mapSingleInvoicePayload(extractEnvelopeData(response));
    } on ApiException catch (error) {
      if (error.statusCode == 404) {
        return null;
      }
      throw _mapError(
        error,
        fallbackMessage: 'Unable to retry invoice payment right now.',
      );
    } catch (error) {
      throw _mapError(
        error,
        fallbackMessage: 'Unable to retry invoice payment right now.',
      );
    }
  }

  @override
  Future<List<MarketplaceOrgSummary>> listOrgs() async {
    try {
      final response = await _apiClient.get(MarketplaceEndpoints.orgs);
      final payload = extractEnvelopeData(response);
      final rows = _extractList(payload, key: 'orgs');
      return rows
          .map((row) => MarketplaceOrgSummary.fromJson(row))
          .toList(growable: false);
    } catch (error) {
      throw _mapError(
        error,
        fallbackMessage: 'Unable to load your teams right now.',
      );
    }
  }

  @override
  Future<List<MarketplacePurchaseSnapshot>> fetchOrgPurchases(
    String orgId,
  ) async {
    try {
      final response = await _apiClient.get(
        MarketplaceEndpoints.orgPurchases(orgId),
      );
      final payload = extractEnvelopeData(response);
      final rows = _extractList(payload, key: 'purchases');
      return rows
          .map((row) => MarketplacePurchaseSnapshot.fromJson(row))
          .toList(growable: false);
    } catch (error) {
      throw _mapError(
        error,
        fallbackMessage: 'Unable to load team purchases right now.',
      );
    }
  }

  @override
  Future<MarketplaceInviteResult> createOrgInvite({
    required String orgId,
    required String email,
    required String role,
  }) async {
    try {
      final response = await _apiClient.post(
        MarketplaceEndpoints.orgInvites(orgId),
        body: <String, dynamic>{'email': email, 'role': role},
      );
      final payload = extractEnvelopeData(response);
      final map = _toMap(payload);
      return MarketplaceInviteResult.fromJson(map);
    } catch (error) {
      throw _mapError(
        error,
        fallbackMessage: 'Unable to create invite right now.',
      );
    }
  }

  @override
  Future<MarketplaceOrgSummary?> acceptOrgInvite(String token) async {
    try {
      final response = await _apiClient.post(
        MarketplaceEndpoints.acceptOrgInvite,
        body: <String, dynamic>{'token': token},
      );
      final payload = extractEnvelopeData(response);
      final map = _toMap(payload);
      if (map.isEmpty) {
        return null;
      }
      final org = map['org'];
      if (org is Map) {
        return MarketplaceOrgSummary.fromJson(
          org.map(
            (key, value) => MapEntry<String, dynamic>(key.toString(), value),
          ),
        );
      }
      return MarketplaceOrgSummary.fromJson(map);
    } catch (error) {
      throw _mapError(
        error,
        fallbackMessage: 'Unable to accept invite right now.',
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

List<Map<String, dynamic>> _extractList(
  dynamic payload, {
  required String key,
}) {
  if (payload is List) {
    return payload
        .whereType<Map>()
        .map(
          (item) =>
              item.map((k, v) => MapEntry<String, dynamic>(k.toString(), v)),
        )
        .toList(growable: false);
  }
  final map = _toMap(payload);
  final direct = map[key];
  if (direct is List) {
    return direct
        .whereType<Map>()
        .map(
          (item) =>
              item.map((k, v) => MapEntry<String, dynamic>(k.toString(), v)),
        )
        .toList(growable: false);
  }
  return const <Map<String, dynamic>>[];
}

Map<String, dynamic> _toMap(dynamic payload) {
  if (payload is Map<String, dynamic>) {
    return payload;
  }
  if (payload is Map) {
    return payload.map((k, v) => MapEntry<String, dynamic>(k.toString(), v));
  }
  return <String, dynamic>{};
}
