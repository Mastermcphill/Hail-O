import 'marketplace_offer_repository.dart';

class InMemoryMarketplaceOfferRepository implements MarketplaceOfferRepository {
  InMemoryMarketplaceOfferRepository()
    : _offers = const <MarketplaceOfferRecord>[
        MarketplaceOfferRecord(
          id: 'offer_sedan_01',
          title: 'Budget Sedan',
          description: 'Sedan Essentials',
          currency: 'NGN',
          priceMinor: 4200,
          interval: 'per trip',
          perks: <String>[
            'Air conditioning',
            'Verified driver',
            'Cashless payment',
          ],
          sortRank: 10,
        ),
        MarketplaceOfferRecord(
          id: 'offer_suv_02',
          title: 'Comfort SUV',
          description: 'SUV Plus',
          currency: 'NGN',
          priceMinor: 5900,
          interval: 'per trip',
          perks: <String>[
            'Large luggage space',
            'Premium interior',
            'Priority support',
          ],
          sortRank: 20,
        ),
        MarketplaceOfferRecord(
          id: 'offer_van_03',
          title: 'Family Van',
          description: 'Van Group',
          currency: 'NGN',
          priceMinor: 7100,
          interval: 'per trip',
          perks: <String>[
            'Group-friendly',
            'Accessible boarding',
            'Child seat options',
          ],
          sortRank: 30,
        ),
      ];

  final List<MarketplaceOfferRecord> _offers;

  @override
  Future<MarketplaceOfferRecord?> findActiveOfferById(String offerId) async {
    for (final offer in _offers) {
      if (offer.id == offerId) {
        return offer;
      }
    }
    return null;
  }

  @override
  Future<List<MarketplaceOfferRecord>> listActiveOffers() async {
    return List<MarketplaceOfferRecord>.from(_offers);
  }
}
