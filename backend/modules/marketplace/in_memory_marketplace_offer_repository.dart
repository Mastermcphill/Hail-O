import 'package:uuid/uuid.dart';

import 'marketplace_offer_repository.dart';

class InMemoryMarketplaceOfferRepository implements MarketplaceOfferRepository {
  InMemoryMarketplaceOfferRepository({Uuid? uuid, DateTime Function()? nowUtc})
    : _uuid = uuid ?? const Uuid(),
      _nowUtc = nowUtc ?? (() => DateTime.now().toUtc()),
      _offers = const <MarketplaceOfferRecord>[
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

  final Uuid _uuid;
  final DateTime Function() _nowUtc;
  final List<MarketplaceOfferRecord> _offers;
  final Map<String, MarketplacePurchaseRecord> _purchasesById =
      <String, MarketplacePurchaseRecord>{};
  final Map<String, String> _purchaseIdByUserAndIdempotency =
      <String, String>{};

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

  @override
  Future<MarketplacePurchaseRecord> createOrGetPurchase({
    required String userId,
    required String offerId,
    required int seatCount,
    required String idempotencyKey,
    required String provider,
  }) async {
    final key = '$userId::$idempotencyKey';
    final existingPurchaseId = _purchaseIdByUserAndIdempotency[key];
    if (existingPurchaseId != null) {
      final existing = _purchasesById[existingPurchaseId];
      if (existing != null) {
        return existing;
      }
    }

    final offer = await findActiveOfferById(offerId);
    if (offer == null) {
      throw const MarketplaceRepositoryStateException(code: 'offer_not_found');
    }

    final now = _nowUtc();
    final purchase = MarketplacePurchaseRecord(
      id: _uuid.v4(),
      userId: userId,
      offerId: offer.id,
      offerTitle: offer.title,
      status: 'PENDING',
      currency: offer.currency,
      totalAmountMinor: offer.priceMinor * seatCount,
      seatCount: seatCount,
      idempotencyKey: idempotencyKey,
      createdAt: now,
      updatedAt: now,
    );
    _purchasesById[purchase.id] = purchase;
    _purchaseIdByUserAndIdempotency[key] = purchase.id;
    return purchase;
  }

  @override
  Future<MarketplacePurchaseRecord?> findPurchaseById({
    required String userId,
    required String purchaseId,
  }) async {
    final record = _purchasesById[purchaseId];
    if (record == null || record.userId != userId) {
      return null;
    }
    return record;
  }

  @override
  Future<MarketplacePurchaseRecord?> findPurchaseByIdempotencyKey({
    required String userId,
    required String idempotencyKey,
  }) async {
    final key = '$userId::$idempotencyKey';
    final purchaseId = _purchaseIdByUserAndIdempotency[key];
    if (purchaseId == null) {
      return null;
    }
    return _purchasesById[purchaseId];
  }
}
