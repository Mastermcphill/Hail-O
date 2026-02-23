abstract class MarketplaceOfferRepository {
  Future<List<MarketplaceOfferRecord>> listActiveOffers();

  Future<MarketplaceOfferRecord?> findActiveOfferById(String offerId);

  Future<MarketplacePurchaseRecord> createOrGetPurchase({
    required String userId,
    required String offerId,
    required int seatCount,
    required String idempotencyKey,
    required String provider,
  });

  Future<MarketplacePurchaseRecord?> findPurchaseByIdempotencyKey({
    required String userId,
    required String idempotencyKey,
  });

  Future<MarketplacePurchaseRecord?> findPurchaseById({
    required String userId,
    required String purchaseId,
  });
}

class MarketplaceOfferRecord {
  const MarketplaceOfferRecord({
    required this.id,
    required this.title,
    required this.description,
    required this.currency,
    required this.priceMinor,
    required this.interval,
    required this.perks,
    required this.sortRank,
  });

  final String id;
  final String title;
  final String description;
  final String currency;
  final int priceMinor;
  final String interval;
  final List<String> perks;
  final int sortRank;
}

class MarketplacePurchaseRecord {
  const MarketplacePurchaseRecord({
    required this.id,
    required this.userId,
    required this.offerId,
    required this.offerTitle,
    required this.status,
    required this.currency,
    required this.totalAmountMinor,
    required this.seatCount,
    required this.idempotencyKey,
    required this.createdAt,
    required this.updatedAt,
  });

  final String id;
  final String userId;
  final String offerId;
  final String offerTitle;
  final String status;
  final String currency;
  final int totalAmountMinor;
  final int seatCount;
  final String idempotencyKey;
  final DateTime createdAt;
  final DateTime updatedAt;
}

class MarketplaceRepositoryStateException implements Exception {
  const MarketplaceRepositoryStateException({required this.code});

  final String code;
}
