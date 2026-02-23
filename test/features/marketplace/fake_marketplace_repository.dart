import 'package:hailo_core/core/api/api_errors.dart';
import 'package:hailo_core/features/marketplace/data/marketplace_repository.dart';
import 'package:hailo_core/features/marketplace/models/offer.dart';
import 'package:hailo_core/features/marketplace/models/org_summary.dart';
import 'package:hailo_core/features/marketplace/models/paywall_copy.dart';
import 'package:hailo_core/features/marketplace/models/purchase_snapshot.dart';
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

  bool throwOnOffers = false;

  @override
  Future<MarketplaceFetchResult<List<MarketplaceOffer>>> fetchOffers({
    String? ifNoneMatch,
    DateTime? ifModifiedSince,
  }) async {
    if (throwOnOffers) {
      throw ApiException(
        statusCode: 503,
        code: 'NETWORK_DOWN',
        message: 'offline',
      );
    }
    return MarketplaceFetchResult<List<MarketplaceOffer>>(
      data: offers,
      notModified: false,
      etag: 'offers-etag',
    );
  }

  @override
  Future<MarketplaceFetchResult<MarketplacePaywallCopy>> fetchPaywallCopy(
    String offerId,
  ) async {
    return MarketplaceFetchResult<MarketplacePaywallCopy>(
      data: paywallCopy,
      notModified: false,
      etag: 'paywall-etag',
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
    if (createFailuresRemaining > 0) {
      createFailuresRemaining -= 1;
      throw ApiException(
        statusCode: 503,
        code: 'NETWORK_DOWN',
        message: 'offline',
      );
    }
    final existing = await restorePurchase(idempotencyKey);
    if (existing != null) {
      return existing;
    }
    final snapshot = MarketplacePurchaseSnapshot(
      purchaseId: 'purchase-$idempotencyKey',
      offerId: offerId,
      seatCount: seatCount,
      status: 'active',
      createdAt: DateTime.now().toUtc(),
      totalAmount: 1000,
      currency: 'NGN',
      version: 1,
      assignmentsVersion: 1,
      assignments: assignments,
      orgId: orgId,
      orgName: _orgNameForId(orgId),
      requesterRole: _orgRoleForId(orgId),
    );
    purchases[snapshot.purchaseId] = snapshot;
    purchases['idem:$idempotencyKey'] = snapshot;
    if (orgId != null && orgId.trim().isNotEmpty) {
      final rows = purchasesByOrg.putIfAbsent(
        orgId,
        () => <MarketplacePurchaseSnapshot>[],
      );
      rows.removeWhere((entry) => entry.purchaseId == snapshot.purchaseId);
      rows.add(snapshot);
    }
    return snapshot;
  }

  @override
  Future<MarketplacePurchaseSnapshot?> restorePurchase(
    String idempotencyKey,
  ) async {
    return purchases['idem:$idempotencyKey'];
  }

  @override
  Future<MarketplaceFetchResult<MarketplacePurchaseSnapshot>> fetchPurchase(
    String purchaseId, {
    String? ifNoneMatch,
    DateTime? ifModifiedSince,
  }) async {
    final snapshot =
        purchases[purchaseId] ??
        MarketplacePurchaseSnapshot(
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
    return MarketplaceFetchResult<MarketplacePurchaseSnapshot>(
      data: snapshot,
      notModified: false,
      etag: 'purchase-$purchaseId',
    );
  }

  @override
  Future<MarketplacePurchaseSnapshot> updateSeats({
    required String purchaseId,
    required int seatCount,
    required int baseVersion,
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
            'latest': <String, dynamic>{
              'purchaseId': purchaseId,
              'offerId': 'starter_monthly',
              'seatCount': 2,
              'status': 'active',
              'createdAt': DateTime.now().toUtc().toIso8601String(),
              'totalAmount': 1000,
              'currency': 'NGN',
              'version': 3,
              'assignments_version': 3,
              'assignments': const <Map<String, dynamic>>[],
            },
          },
        },
      );
    }
    final updated = MarketplacePurchaseSnapshot(
      purchaseId: purchaseId,
      offerId: 'starter_monthly',
      seatCount: seatCount,
      status: 'active',
      createdAt: DateTime.now().toUtc(),
      totalAmount: 1000,
      currency: 'NGN',
      version: baseVersion + 1,
      assignmentsVersion: baseVersion + 1,
      assignments: const <MarketplaceAssignment>[],
      orgId: _firstOrgId,
      orgName: _orgNameForId(_firstOrgId),
      requesterRole: _orgRoleForId(_firstOrgId),
    );
    purchases[purchaseId] = updated;
    return updated;
  }

  @override
  Future<MarketplacePurchaseSnapshot> updateAssignments({
    required String purchaseId,
    required List<MarketplaceAssignment> assignments,
    required int baseVersion,
  }) async {
    final updated = MarketplacePurchaseSnapshot(
      purchaseId: purchaseId,
      offerId: 'starter_monthly',
      seatCount: assignments.length,
      status: 'active',
      createdAt: DateTime.now().toUtc(),
      totalAmount: 1000,
      currency: 'NGN',
      version: baseVersion + 1,
      assignmentsVersion: baseVersion + 1,
      assignments: assignments,
      orgId: _firstOrgId,
      orgName: _orgNameForId(_firstOrgId),
      requesterRole: _orgRoleForId(_firstOrgId),
    );
    purchases[purchaseId] = updated;
    return updated;
  }

  @override
  Future<MarketplacePurchaseSnapshot> changePlan({
    required String purchaseId,
    required String offerId,
    required int baseVersion,
    required String idempotencyKey,
  }) async {
    final updated = MarketplacePurchaseSnapshot(
      purchaseId: purchaseId,
      offerId: offerId,
      seatCount: 1,
      status: 'active',
      createdAt: DateTime.now().toUtc(),
      totalAmount: 2000,
      currency: 'NGN',
      version: baseVersion + 1,
      assignmentsVersion: baseVersion + 1,
      assignments: const <MarketplaceAssignment>[],
      orgId: _firstOrgId,
      orgName: _orgNameForId(_firstOrgId),
      requesterRole: _orgRoleForId(_firstOrgId),
    );
    purchases[purchaseId] = updated;
    return updated;
  }

  @override
  Future<MarketplaceFetchResult<List<MarketplaceTimelineEvent>>> fetchTimeline(
    String purchaseId, {
    DateTime? sinceUtc,
    int limit = 200,
    String? ifNoneMatch,
    DateTime? ifModifiedSince,
  }) async {
    final events = sinceUtc == null ? initialTimeline : incrementalTimeline;
    return MarketplaceFetchResult<List<MarketplaceTimelineEvent>>(
      data: events,
      notModified: false,
      etag: 'timeline-$purchaseId',
      latestEventAt: events.isNotEmpty
          ? events.last.timestamp?.toIso8601String()
          : null,
      cursor: events.isNotEmpty ? events.last.cursor : null,
    );
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
