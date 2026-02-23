class MarketplaceEndpoints {
  static const orgs = '/orgs';

  static String org(String orgId) => '/orgs/${Uri.encodeComponent(orgId)}';

  static String orgMembers(String orgId) => '${org(orgId)}/members';

  static String orgInvites(String orgId) => '${org(orgId)}/invites';

  static const orgInvitesAccept = '/orgs/invites/accept';

  static String orgBillingPurchases(String orgId) =>
      '${org(orgId)}/billing/purchases';

  static String orgBillingLedger(String orgId) =>
      '${org(orgId)}/billing/ledger';

  static const offers = '/marketplace/offers';

  static String offerPaywall(String offerId) =>
      '/marketplace/offers/${Uri.encodeComponent(offerId)}/paywall';

  static const purchases = '/marketplace/purchases';

  static String purchase(String purchaseId) =>
      '/marketplace/purchases/${Uri.encodeComponent(purchaseId)}';

  static String purchaseRestore(String idempotencyKey) =>
      '/marketplace/purchases/restore'
      '?idempotencyKey=${Uri.encodeQueryComponent(idempotencyKey)}';

  static String purchaseSeats(String purchaseId) =>
      '${purchase(purchaseId)}/seats';

  static String purchaseAssignments(String purchaseId) =>
      '${purchase(purchaseId)}/assignments';

  static String purchaseChangePlan(String purchaseId) =>
      '${purchase(purchaseId)}/change-plan';

  static String purchaseTimeline(
    String purchaseId, {
    DateTime? sinceUtc,
    int? limit,
  }) {
    final query = <String, String>{};
    if (sinceUtc != null) {
      query['since'] = sinceUtc.toIso8601String();
    }
    if (limit != null) {
      query['limit'] = '$limit';
    }
    final base = '${purchase(purchaseId)}/timeline';
    if (query.isEmpty) {
      return base;
    }
    return '$base?${Uri(queryParameters: query).query}';
  }
}
