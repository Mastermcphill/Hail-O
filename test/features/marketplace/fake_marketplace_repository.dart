import 'package:hailo_core/core/api/api_errors.dart';
import 'package:hailo_core/features/marketplace/data/marketplace_repository.dart';
import 'package:hailo_core/features/marketplace/models/billing_invoice.dart';
import 'package:hailo_core/features/marketplace/models/offer.dart';
import 'package:hailo_core/features/marketplace/models/org_summary.dart';
import 'package:hailo_core/features/marketplace/models/paywall_copy.dart';
import 'package:hailo_core/features/marketplace/models/pricing_breakdown.dart';
import 'package:hailo_core/features/marketplace/models/purchase_receipt.dart';
import 'package:hailo_core/features/marketplace/models/purchase_snapshot.dart';
import 'package:hailo_core/features/marketplace/models/seat_selection.dart';
import 'package:hailo_core/features/marketplace/models/timeline_event.dart';

class FakeMarketplaceRepository implements MarketplaceRepository {
  List<MarketplaceOffer> offers = <MarketplaceOffer>[
    const MarketplaceOffer(
      id: 'starter_monthly',
      title: 'Starter Monthly',
      subtitle: 'Core access',
      price: 1000,
      currency: 'NGN',
      interval: 'month',
      perks: <String>['A'],
    ),
  ];

  MarketplacePaywallCopy paywallCopy = const MarketplacePaywallCopy(
    offerId: 'starter_monthly',
    headline: 'Paywall',
    subhead: 'Subhead',
    bullets: <String>['A'],
    legalText: 'Legal',
  );

  final Map<String, MarketplacePurchaseSnapshot> purchases =
      <String, MarketplacePurchaseSnapshot>{};
  final Map<String, List<MarketplacePurchaseSnapshot>> purchasesByOrg =
      <String, List<MarketplacePurchaseSnapshot>>{};

  List<MarketplaceOrgSummary> orgs = const <MarketplaceOrgSummary>[
    MarketplaceOrgSummary(
      id: 'org-personal',
      name: 'Personal Team',
      slug: 'personal-team',
      role: 'owner',
      memberStatus: 'active',
    ),
  ];

  String? lastInviteToken;
  String? lastInviteOrgId;
  String? lastInviteEmail;
  String? lastInviteRole;

  int createFailuresRemaining = 0;
  int updateSeatFailuresRemaining = 0;
  int updateSeatConflictRemaining = 0;
  int updateSeatCalls = 0;

  List<MarketplaceTimelineEvent> initialTimeline = <MarketplaceTimelineEvent>[];
  List<MarketplaceTimelineEvent> incrementalTimeline =
      <MarketplaceTimelineEvent>[];
  final Map<String, int> _timelineReadsByPurchaseId = <String, int>{};

  bool throwOnOffers = false;

  @override
  Future<List<MarketplaceOffer>> fetchOffers() async {
    if (throwOnOffers) {
      throw ApiException(
        statusCode: 503,
        code: 'NETWORK_DOWN',
        message: 'offline',
      );
    }
    return List<MarketplaceOffer>.from(offers);
  }

  @override
  Future<MarketplacePaywallCopy> fetchPaywallCopy(String offerId) async {
    return paywallCopy;
  }

  @override
  Future<PricingBreakdown> fetchPricingPreview({
    required String orgId,
    required String offerId,
    required int seats,
  }) async {
    return PricingBreakdown(
      orgId: orgId,
      offerId: offerId,
      seats: seats,
      currency: 'NGN',
      baseMinor: seats * 1000,
      couponDiscountMinor: 0,
      referralDiscountMinor: 0,
      creditsAppliedMinor: 0,
      finalDueMinor: seats * 1000,
    );
  }

  @override
  Future<PricingBreakdown> applyCoupon({
    required String orgId,
    required String couponCode,
    required String offerId,
    required int seats,
  }) async {
    return PricingBreakdown(
      orgId: orgId,
      offerId: offerId,
      seats: seats,
      currency: 'NGN',
      baseMinor: seats * 1000,
      couponDiscountMinor: 500,
      referralDiscountMinor: 0,
      creditsAppliedMinor: 0,
      finalDueMinor: (seats * 1000) - 500,
      appliedCoupon: couponCode,
    );
  }

  @override
  Future<PricingBreakdown> removeCoupon({
    required String orgId,
    required String offerId,
    required int seats,
  }) async {
    return PricingBreakdown(
      orgId: orgId,
      offerId: offerId,
      seats: seats,
      currency: 'NGN',
      baseMinor: seats * 1000,
      couponDiscountMinor: 0,
      referralDiscountMinor: 0,
      creditsAppliedMinor: 0,
      finalDueMinor: seats * 1000,
    );
  }

  @override
  Future<PricingBreakdown> applyReferral({
    required String orgId,
    required String referralCode,
    required String offerId,
    required int seats,
  }) async {
    return PricingBreakdown(
      orgId: orgId,
      offerId: offerId,
      seats: seats,
      currency: 'NGN',
      baseMinor: seats * 1000,
      couponDiscountMinor: 0,
      referralDiscountMinor: 250,
      creditsAppliedMinor: 0,
      finalDueMinor: (seats * 1000) - 250,
      appliedReferral: referralCode,
    );
  }

  @override
  Future<String> createCheckout(
    SeatSelection selection, {
    required String idempotencyKey,
  }) async {
    if (createFailuresRemaining > 0) {
      createFailuresRemaining -= 1;
      throw ApiException(
        statusCode: 503,
        code: 'NETWORK_DOWN',
        message: 'offline',
      );
    }
    final existing = purchases['idem:$idempotencyKey'];
    if (existing != null) {
      return existing.purchaseId;
    }
    final snapshot = MarketplacePurchaseSnapshot(
      purchaseId: 'purchase-$idempotencyKey',
      offerId: selection.offerId,
      seatCount: selection.seatCount,
      status: 'active',
      createdAt: DateTime.now().toUtc(),
      totalAmount: 1000,
      currency: 'NGN',
      version: 1,
      assignmentsVersion: 1,
      assignments: selection.assignments
          .map(
            (entry) => MarketplaceAssignment(
              seatIndex: entry.seatNumber,
              name: entry.name,
              email: entry.email,
            ),
          )
          .toList(growable: false),
      orgId: _firstOrgId,
      orgName: _orgNameForId(_firstOrgId),
      requesterRole: _orgRoleForId(_firstOrgId),
    );
    purchases[snapshot.purchaseId] = snapshot;
    purchases['idem:$idempotencyKey'] = snapshot;
    return snapshot.purchaseId;
  }

  @override
  Future<String?> restorePurchaseByIdempotencyKey(String idempotencyKey) async {
    return purchases['idem:$idempotencyKey']?.purchaseId;
  }

  @override
  Future<PurchaseReceipt?> fetchPurchaseReceipt(String purchaseId) async {
    final snapshot = purchases[purchaseId];
    if (snapshot == null) {
      return null;
    }
    return _toReceipt(snapshot);
  }

  @override
  Future<PurchaseReceipt> updateSeatCount({
    required String purchaseId,
    required int seatCount,
  }) async {
    updateSeatCalls += 1;
    if (updateSeatFailuresRemaining > 0) {
      updateSeatFailuresRemaining -= 1;
      throw ApiException(
        statusCode: 503,
        code: 'NETWORK_DOWN',
        message: 'retry later',
      );
    }
    if (updateSeatConflictRemaining > 0) {
      updateSeatConflictRemaining -= 1;
      throw ApiException(
        statusCode: 409,
        code: 'VERSION_CONFLICT',
        message: 'conflict',
        envelope: <String, dynamic>{
          'ok': false,
          'error_code': 'VERSION_CONFLICT',
          'message': 'conflict',
          'data': <String, dynamic>{
            'latest': <String, dynamic>{'version': 3},
          },
        },
      );
    }
    final existing = purchases[purchaseId] ?? _defaultSnapshot(purchaseId);
    final updated = MarketplacePurchaseSnapshot(
      purchaseId: purchaseId,
      offerId: existing.offerId,
      seatCount: seatCount,
      status: 'active',
      createdAt: existing.createdAt,
      totalAmount: existing.totalAmount,
      currency: existing.currency,
      version: existing.version + 1,
      assignmentsVersion: existing.assignmentsVersion + 1,
      assignments: existing.assignments,
      orgId: existing.orgId,
      orgName: existing.orgName,
      requesterRole: existing.requesterRole,
    );
    purchases[purchaseId] = updated;
    return _toReceipt(updated);
  }

  @override
  Future<PurchaseReceipt> updateAssignments({
    required String purchaseId,
    required List<SeatAssignment> assignments,
  }) async {
    final existing = purchases[purchaseId] ?? _defaultSnapshot(purchaseId);
    final updated = MarketplacePurchaseSnapshot(
      purchaseId: purchaseId,
      offerId: existing.offerId,
      seatCount: assignments.length,
      status: 'active',
      createdAt: existing.createdAt,
      totalAmount: existing.totalAmount,
      currency: existing.currency,
      version: existing.version + 1,
      assignmentsVersion: existing.assignmentsVersion + 1,
      assignments: assignments
          .map(
            (entry) => MarketplaceAssignment(
              seatIndex: entry.seatNumber,
              name: entry.name,
              email: entry.email,
            ),
          )
          .toList(growable: false),
      orgId: existing.orgId,
      orgName: existing.orgName,
      requesterRole: existing.requesterRole,
    );
    purchases[purchaseId] = updated;
    return _toReceipt(updated);
  }

  @override
  Future<String> changePlan({
    required String purchaseId,
    required String newOfferId,
  }) async {
    final existing = purchases[purchaseId] ?? _defaultSnapshot(purchaseId);
    final updated = MarketplacePurchaseSnapshot(
      purchaseId: purchaseId,
      offerId: newOfferId,
      seatCount: existing.seatCount,
      status: 'active',
      createdAt: existing.createdAt,
      totalAmount: existing.totalAmount,
      currency: existing.currency,
      version: existing.version + 1,
      assignmentsVersion: existing.assignmentsVersion + 1,
      assignments: existing.assignments,
      orgId: existing.orgId,
      orgName: existing.orgName,
      requesterRole: existing.requesterRole,
    );
    purchases[purchaseId] = updated;
    return purchaseId;
  }

  @override
  Future<List<MarketplaceTimelineEvent>> fetchTimeline(
    String purchaseId,
  ) async {
    final reads = (_timelineReadsByPurchaseId[purchaseId] ?? 0) + 1;
    _timelineReadsByPurchaseId[purchaseId] = reads;
    final events = reads == 1 ? initialTimeline : incrementalTimeline;
    return List<MarketplaceTimelineEvent>.from(events);
  }

  @override
  Future<List<BillingInvoice>> fetchInvoices(String orgId) async {
    return const <BillingInvoice>[];
  }

  @override
  Future<BillingInvoice?> retryInvoice({
    required String orgId,
    required String invoiceId,
  }) async {
    return null;
  }

  @override
  Future<List<MarketplaceOrgSummary>> listOrgs() async {
    return List<MarketplaceOrgSummary>.from(orgs);
  }

  @override
  Future<List<MarketplacePurchaseSnapshot>> fetchOrgPurchases(
    String orgId,
  ) async {
    return List<MarketplacePurchaseSnapshot>.from(
      purchasesByOrg[orgId] ?? const <MarketplacePurchaseSnapshot>[],
    );
  }

  @override
  Future<MarketplaceInviteResult> createOrgInvite({
    required String orgId,
    required String email,
    required String role,
  }) async {
    lastInviteToken = 'invite-token-${DateTime.now().millisecondsSinceEpoch}';
    lastInviteOrgId = orgId;
    lastInviteEmail = email;
    lastInviteRole = role;
    return MarketplaceInviteResult(
      orgId: orgId,
      email: email,
      role: role,
      token: lastInviteToken!,
    );
  }

  @override
  Future<MarketplaceOrgSummary?> acceptOrgInvite(String token) async {
    if (token.trim().isEmpty || token != lastInviteToken) {
      throw ApiException(
        statusCode: 404,
        code: 'NOT_FOUND',
        message: 'Invite not found',
      );
    }
    final orgId = lastInviteOrgId ?? _firstOrgId;
    final created = MarketplaceOrgSummary(
      id: orgId,
      name: _orgNameForId(orgId),
      slug: 'accepted-${orgId.replaceAll('_', '-')}',
      role: lastInviteRole ?? 'member',
      memberStatus: 'active',
    );
    final existingIndex = orgs.indexWhere((entry) => entry.id == created.id);
    if (existingIndex >= 0) {
      orgs = List<MarketplaceOrgSummary>.from(orgs)..[existingIndex] = created;
    } else {
      orgs = List<MarketplaceOrgSummary>.from(orgs)..add(created);
    }
    return created;
  }

  MarketplacePurchaseSnapshot _defaultSnapshot(String purchaseId) {
    return MarketplacePurchaseSnapshot(
      purchaseId: purchaseId,
      offerId: 'starter_monthly',
      seatCount: 1,
      status: 'active',
      createdAt: DateTime.now().toUtc(),
      totalAmount: 1000,
      currency: 'NGN',
      version: 1,
      assignmentsVersion: 1,
      assignments: const <MarketplaceAssignment>[],
      orgId: _firstOrgId,
      orgName: _orgNameForId(_firstOrgId),
      requesterRole: _orgRoleForId(_firstOrgId),
    );
  }

  PurchaseReceipt _toReceipt(MarketplacePurchaseSnapshot snapshot) {
    return PurchaseReceipt(
      purchaseId: snapshot.purchaseId,
      offerId: snapshot.offerId,
      offerTitle: snapshot.offerId,
      seatCount: snapshot.seatCount,
      totalPriceMinor: snapshot.totalAmount,
      status: snapshot.status,
      createdAt: snapshot.createdAt ?? DateTime.now().toUtc(),
      assignments: snapshot.assignments
          .map(
            (entry) => SeatAssignment(
              seatNumber: entry.seatIndex,
              name: entry.name,
              email: entry.email,
            ),
          )
          .toList(growable: false),
    );
  }

  String get _firstOrgId => orgs.isEmpty ? 'org-personal' : orgs.first.id;

  String _orgNameForId(String? orgId) {
    if (orgId == null || orgId.trim().isEmpty) {
      return 'Personal Team';
    }
    for (final org in orgs) {
      if (org.id == orgId) {
        return org.name;
      }
    }
    return 'Team';
  }

  String _orgRoleForId(String? orgId) {
    if (orgId == null || orgId.trim().isEmpty) {
      return 'owner';
    }
    for (final org in orgs) {
      if (org.id == orgId) {
        return org.role;
      }
    }
    return 'viewer';
  }
}
