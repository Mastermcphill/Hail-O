import '../models/offer.dart';
import '../models/org_summary.dart';
import '../models/paywall_copy.dart';
import '../models/purchase_snapshot.dart';
import '../models/timeline_event.dart';

class MarketplaceFetchResult<T> {
  const MarketplaceFetchResult({
    required this.data,
    required this.notModified,
    this.etag,
    this.latestEventAt,
    this.cursor,
  });

  final T? data;
  final bool notModified;
  final String? etag;
  final String? latestEventAt;
  final String? cursor;
}

abstract class MarketplaceRepository {
  Future<MarketplaceFetchResult<List<MarketplaceOffer>>> fetchOffers({
    String? ifNoneMatch,
    DateTime? ifModifiedSince,
  });

  Future<MarketplaceFetchResult<MarketplacePaywallCopy>> fetchPaywallCopy(
    String offerId,
  );

  Future<MarketplacePurchaseSnapshot> createPurchase({
    required String offerId,
    required int seatCount,
    required List<MarketplaceAssignment> assignments,
    required String idempotencyKey,
    String? orgId,
  });

  Future<MarketplacePurchaseSnapshot?> restorePurchase(String idempotencyKey);

  Future<MarketplaceFetchResult<MarketplacePurchaseSnapshot>> fetchPurchase(
    String purchaseId, {
    String? ifNoneMatch,
    DateTime? ifModifiedSince,
  });

  Future<MarketplacePurchaseSnapshot> updateSeats({
    required String purchaseId,
    required int seatCount,
    required int baseVersion,
  });

  Future<MarketplacePurchaseSnapshot> updateAssignments({
    required String purchaseId,
    required List<MarketplaceAssignment> assignments,
    required int baseVersion,
  });

  Future<MarketplacePurchaseSnapshot> changePlan({
    required String purchaseId,
    required String offerId,
    required int baseVersion,
    required String idempotencyKey,
  });

  Future<MarketplaceFetchResult<List<MarketplaceTimelineEvent>>> fetchTimeline(
    String purchaseId, {
    DateTime? sinceUtc,
    int limit,
    String? ifNoneMatch,
    DateTime? ifModifiedSince,
  });

  Future<List<MarketplaceOrgSummary>> listOrgs();

  Future<List<MarketplacePurchaseSnapshot>> fetchOrgPurchases(String orgId);

  Future<MarketplaceInviteResult> createOrgInvite({
    required String orgId,
    required String email,
    required String role,
  });

  Future<MarketplaceOrgSummary?> acceptOrgInvite(String token);
}
