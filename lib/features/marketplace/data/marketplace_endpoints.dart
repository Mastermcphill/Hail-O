class MarketplaceEndpoints {
  static const offers = '/marketplace/offers';
  static String offerPaywall(String offerId) =>
      '/marketplace/offers/$offerId/paywall';

  static const purchases = '/marketplace/purchases';
  static String purchaseTimeline(String purchaseId) =>
      '/marketplace/purchases/$purchaseId/timeline';

  static String restorePurchase(String idempotencyKey) {
    final query = Uri.encodeQueryComponent(idempotencyKey);
    return '/marketplace/purchases/restore?idempotencyKey=$query';
  }
}
