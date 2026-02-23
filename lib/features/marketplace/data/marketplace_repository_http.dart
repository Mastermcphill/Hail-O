import 'dart:io';

import '../../../core/api/api_client.dart';
import '../../../core/api/api_errors.dart';
import 'marketplace_endpoints.dart';
import 'marketplace_repository.dart';
import '../models/offer.dart';
import '../models/org_summary.dart';
import '../models/paywall_copy.dart';
import '../models/purchase_snapshot.dart';
import '../models/timeline_event.dart';

class MarketplaceRepositoryHttp implements MarketplaceRepository {
  MarketplaceRepositoryHttp({required ApiClient apiClient})
    : _apiClient = apiClient;

  final ApiClient _apiClient;

  @override
  Future<MarketplaceFetchResult<List<MarketplaceOffer>>> fetchOffers({
    String? ifNoneMatch,
    DateTime? ifModifiedSince,
  }) async {
    final result = await _apiClient.getDetailed(
      MarketplaceEndpoints.offers,
      extraHeaders: _conditionalHeaders(
        ifNoneMatch: ifNoneMatch,
        ifModifiedSince: ifModifiedSince,
      ),
    );
    if (result.notModified) {
      return MarketplaceFetchResult<List<MarketplaceOffer>>(
        data: null,
        notModified: true,
        etag: result.headers['etag'],
      );
    }

    final envelopeData = _envelopeData(result.data);
    final source = envelopeData is List
        ? envelopeData
        : (envelopeData is Map
              ? (envelopeData['offers'] as List<dynamic>? ?? const <dynamic>[])
              : const <dynamic>[]);
    final offers = source
        .whereType<Map>()
        .map(
          (item) => MarketplaceOffer.fromJson(
            item.map(
              (key, value) => MapEntry<String, dynamic>(key.toString(), value),
            ),
          ),
        )
        .toList(growable: false);
    return MarketplaceFetchResult<List<MarketplaceOffer>>(
      data: offers,
      notModified: false,
      etag: result.headers['etag'],
    );
  }

  @override
  Future<MarketplaceFetchResult<MarketplacePaywallCopy>> fetchPaywallCopy(
    String offerId,
  ) async {
    final result = await _apiClient.getDetailed(
      MarketplaceEndpoints.offerPaywall(offerId),
    );
    final data = _asMap(_envelopeData(result.data));
    return MarketplaceFetchResult<MarketplacePaywallCopy>(
      data: MarketplacePaywallCopy.fromJson(data),
      notModified: false,
      etag: result.headers['etag'],
    );
  }

  @override
  Future<MarketplacePurchaseSnapshot> createPurchase({
    required String offerId,
    required int seatCount,
    required List<MarketplaceAssignment> assignments,
    required String idempotencyKey,
    String? orgId,
  }) async {
    final body = <String, dynamic>{
      'offerId': offerId,
      'seatCount': seatCount,
      'assignments': assignments
          .map((assignment) => assignment.toJson())
          .toList(growable: false),
    };
    if (orgId != null && orgId.trim().isNotEmpty) {
      body['org_id'] = orgId.trim();
    }
    final result = await _apiClient.postDetailed(
      MarketplaceEndpoints.purchases,
      idempotencyKey: idempotencyKey,
      body: body,
    );
    return _purchaseFromDynamic(_envelopeData(result.data));
  }

  @override
  Future<MarketplacePurchaseSnapshot?> restorePurchase(
    String idempotencyKey,
  ) async {
    try {
      final result = await _apiClient.getDetailed(
        MarketplaceEndpoints.purchaseRestore(idempotencyKey),
      );
      return _purchaseFromDynamic(_envelopeData(result.data));
    } on ApiException catch (error) {
      if (error.statusCode == 404) {
        return null;
      }
      rethrow;
    }
  }

  @override
  Future<MarketplaceFetchResult<MarketplacePurchaseSnapshot>> fetchPurchase(
    String purchaseId, {
    String? ifNoneMatch,
    DateTime? ifModifiedSince,
  }) async {
    final result = await _apiClient.getDetailed(
      MarketplaceEndpoints.purchase(purchaseId),
      extraHeaders: _conditionalHeaders(
        ifNoneMatch: ifNoneMatch,
        ifModifiedSince: ifModifiedSince,
      ),
    );
    if (result.notModified) {
      return MarketplaceFetchResult<MarketplacePurchaseSnapshot>(
        data: null,
        notModified: true,
        etag: result.headers['etag'],
      );
    }
    final snapshot = _purchaseFromDynamic(_envelopeData(result.data));
    return MarketplaceFetchResult<MarketplacePurchaseSnapshot>(
      data: snapshot,
      notModified: false,
      etag: result.headers['etag'],
    );
  }

  @override
  Future<MarketplacePurchaseSnapshot> updateSeats({
    required String purchaseId,
    required int seatCount,
    required int baseVersion,
  }) async {
    final result = await _apiClient.patchDetailed(
      MarketplaceEndpoints.purchaseSeats(purchaseId),
      extraHeaders: <String, String>{'If-Match-Version': '$baseVersion'},
      body: <String, dynamic>{'seatCount': seatCount},
    );
    return _purchaseFromDynamic(_envelopeData(result.data));
  }

  @override
  Future<MarketplacePurchaseSnapshot> updateAssignments({
    required String purchaseId,
    required List<MarketplaceAssignment> assignments,
    required int baseVersion,
  }) async {
    final result = await _apiClient.patchDetailed(
      MarketplaceEndpoints.purchaseAssignments(purchaseId),
      extraHeaders: <String, String>{'If-Match-Version': '$baseVersion'},
      body: <String, dynamic>{
        'assignments': assignments
            .map((assignment) => assignment.toJson())
            .toList(growable: false),
      },
    );
    return _purchaseFromDynamic(_envelopeData(result.data));
  }

  @override
  Future<MarketplacePurchaseSnapshot> changePlan({
    required String purchaseId,
    required String offerId,
    required int baseVersion,
    required String idempotencyKey,
  }) async {
    final result = await _apiClient.postDetailed(
      MarketplaceEndpoints.purchaseChangePlan(purchaseId),
      idempotencyKey: idempotencyKey,
      extraHeaders: <String, String>{'If-Match-Version': '$baseVersion'},
      body: <String, dynamic>{'offerId': offerId},
    );
    return _purchaseFromDynamic(_envelopeData(result.data));
  }

  @override
  Future<MarketplaceFetchResult<List<MarketplaceTimelineEvent>>> fetchTimeline(
    String purchaseId, {
    DateTime? sinceUtc,
    int limit = 200,
    String? ifNoneMatch,
    DateTime? ifModifiedSince,
  }) async {
    final result = await _apiClient.getDetailed(
      MarketplaceEndpoints.purchaseTimeline(
        purchaseId,
        sinceUtc: sinceUtc,
        limit: limit,
      ),
      extraHeaders: _conditionalHeaders(
        ifNoneMatch: ifNoneMatch,
        ifModifiedSince: ifModifiedSince,
      ),
    );
    if (result.notModified) {
      return MarketplaceFetchResult<List<MarketplaceTimelineEvent>>(
        data: null,
        notModified: true,
        etag: result.headers['etag'],
      );
    }
    final payload = _envelopeData(result.data);
    final map = _asMap(payload);
    final eventsRaw = (map['events'] as List<dynamic>? ?? const <dynamic>[]);
    final events = eventsRaw
        .whereType<Map>()
        .map(
          (item) => MarketplaceTimelineEvent.fromJson(
            item.map(
              (key, value) => MapEntry<String, dynamic>(key.toString(), value),
            ),
          ),
        )
        .toList(growable: false);
    return MarketplaceFetchResult<List<MarketplaceTimelineEvent>>(
      data: events,
      notModified: false,
      etag: result.headers['etag'],
      latestEventAt: map['latest_event_at']?.toString(),
      cursor: map['cursor']?.toString(),
    );
  }

  @override
  Future<List<MarketplaceOrgSummary>> listOrgs() async {
    final result = await _apiClient.getDetailed(MarketplaceEndpoints.orgs);
    final payload = _envelopeData(result.data);
    final entries = payload is List
        ? payload
        : (payload is Map
              ? (payload['orgs'] as List<dynamic>? ?? const <dynamic>[])
              : const <dynamic>[]);
    return entries
        .whereType<Map>()
        .map(
          (entry) => MarketplaceOrgSummary.fromJson(_toStringKeyedMap(entry)),
        )
        .toList(growable: false);
  }

  @override
  Future<List<MarketplacePurchaseSnapshot>> fetchOrgPurchases(
    String orgId,
  ) async {
    final result = await _apiClient.getDetailed(
      MarketplaceEndpoints.orgBillingPurchases(orgId),
    );
    final payload = _envelopeData(result.data);
    final map = _asMap(payload);
    final rows = (map['purchases'] as List<dynamic>? ?? const <dynamic>[]);
    return rows
        .whereType<Map>()
        .map((row) => _purchaseFromDynamic(row))
        .toList(growable: false);
  }

  @override
  Future<MarketplaceInviteResult> createOrgInvite({
    required String orgId,
    required String email,
    required String role,
  }) async {
    final result = await _apiClient.postDetailed(
      MarketplaceEndpoints.orgInvites(orgId),
      body: <String, dynamic>{'email': email, 'role': role},
    );
    final data = _asMap(_envelopeData(result.data));
    return MarketplaceInviteResult.fromJson(data);
  }

  @override
  Future<MarketplaceOrgSummary?> acceptOrgInvite(String token) async {
    final result = await _apiClient.postDetailed(
      MarketplaceEndpoints.orgInvitesAccept,
      body: <String, dynamic>{'token': token},
    );
    final data = _asMap(_envelopeData(result.data));
    final orgRaw = data['org'];
    if (orgRaw is! Map) {
      return null;
    }
    final membershipRaw = data['membership'];
    final org = _toStringKeyedMap(orgRaw);
    if (membershipRaw is Map) {
      final membership = _toStringKeyedMap(membershipRaw);
      org['role'] = membership['role'];
      org['member_status'] = membership['status'];
    }
    return MarketplaceOrgSummary.fromJson(org);
  }

  Map<String, String> _conditionalHeaders({
    String? ifNoneMatch,
    DateTime? ifModifiedSince,
  }) {
    final headers = <String, String>{};
    if (ifNoneMatch != null && ifNoneMatch.trim().isNotEmpty) {
      headers[HttpHeaders.ifNoneMatchHeader] = ifNoneMatch.trim();
    }
    if (ifModifiedSince != null) {
      headers[HttpHeaders.ifModifiedSinceHeader] = HttpDate.format(
        ifModifiedSince.toUtc(),
      );
    }
    return headers;
  }

  dynamic _envelopeData(Map<String, dynamic> payload) {
    if (payload.containsKey('data')) {
      return payload['data'];
    }
    return payload;
  }

  Map<String, dynamic> _asMap(dynamic value) {
    if (value is Map<String, dynamic>) {
      return value;
    }
    if (value is Map) {
      return _toStringKeyedMap(value);
    }
    return <String, dynamic>{};
  }

  MarketplacePurchaseSnapshot _purchaseFromDynamic(dynamic value) {
    final row = _asMap(value);
    if (row.containsKey('purchaseId') ||
        row.containsKey('purchase_id') ||
        row.containsKey('id')) {
      return MarketplacePurchaseSnapshot.fromJson(row);
    }
    final nestedPurchase = row['purchase'];
    if (nestedPurchase is Map) {
      return MarketplacePurchaseSnapshot.fromJson(
        _toStringKeyedMap(nestedPurchase),
      );
    }
    return MarketplacePurchaseSnapshot.fromJson(row);
  }

  Map<String, dynamic> _toStringKeyedMap(Map value) {
    return value.map(
      (key, item) => MapEntry<String, dynamic>(key.toString(), item),
    );
  }
}
