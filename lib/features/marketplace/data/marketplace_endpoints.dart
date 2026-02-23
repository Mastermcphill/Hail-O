class MarketplaceEndpoints {
  static const offers = '/marketplace/offers';
  static String offerPaywall(String offerId) =>
      '/marketplace/offers/$offerId/paywall';
  static String pricingPreview({
    required String orgId,
    required String offerId,
    required int seats,
  }) {
    final query = Uri(
      queryParameters: <String, String>{
        'org_id': orgId,
        'offer_id': offerId,
        'seats': seats.toString(),
      },
    ).query;
    return '/marketplace/pricing/preview?$query';
  }

  static const applyCoupon = '/marketplace/apply-coupon';
  static const removeCoupon = '/marketplace/remove-coupon';
  static const applyReferral = '/marketplace/apply-referral';

  static const purchases = '/marketplace/purchases';
  static String purchase(String purchaseId) =>
      '/marketplace/purchases/$purchaseId';
  static String purchaseSeats(String purchaseId) =>
      '/marketplace/purchases/$purchaseId/seats';
  static String purchaseAssignments(String purchaseId) =>
      '/marketplace/purchases/$purchaseId/assignments';
  static String changePlan(String purchaseId) =>
      '/marketplace/purchases/$purchaseId/change-plan';
  static String purchaseTimeline(String purchaseId) =>
      '/marketplace/purchases/$purchaseId/timeline';

  static String restorePurchase(String idempotencyKey) {
    final query = Uri.encodeQueryComponent(idempotencyKey);
    return '/marketplace/purchases/restore?idempotencyKey=$query';
  }

  static String orgInvoices(String orgId) => '/orgs/$orgId/billing/invoices';
  static String orgRetryInvoice(String orgId, String invoiceId) =>
      '/orgs/$orgId/billing/retry/$invoiceId';
  static const orgs = '/orgs';
  static String orgPurchases(String orgId) => '/orgs/$orgId/purchases';
  static String orgInvites(String orgId) => '/orgs/$orgId/invites';
  static const acceptOrgInvite = '/orgs/invites/accept';
}
