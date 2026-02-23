abstract class MarketplaceOfferRepository {
  Future<List<MarketplaceOfferRecord>> listActiveOffers();

  Future<MarketplaceOfferRecord?> findActiveOfferById(String offerId);
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
