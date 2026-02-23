import 'package:flutter_test/flutter_test.dart';
import 'package:hailo_core/features/marketplace/data/marketplace_dev_settings.dart';
import 'package:hailo_core/features/marketplace/data/marketplace_repository.dart';
import 'package:hailo_core/features/marketplace/models/offer.dart';
import 'package:hailo_core/features/marketplace/models/paywall_copy.dart';
import 'package:hailo_core/features/marketplace/models/seat_selection.dart';
import 'package:hailo_core/features/marketplace/models/timeline_event.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  group('MarketplaceRepositorySwitching', () {
    final httpOffers = <Offer>[mockOffer('http_offer')];
    final mockOffers = <Offer>[mockOffer('mock_offer')];

    test('uses mock repository by default when mock mode is enabled', () async {
      SharedPreferences.setMockInitialValues(<String, Object>{});
      final repository = createMarketplaceRepositoryForTesting(
        httpRepository: _FakeRepository(offers: httpOffers),
        mockRepository: _FakeRepository(offers: mockOffers),
        devSettings: const MarketplaceDevSettings(),
        mockMode: true,
      );

      final offers = await repository.fetchOffers();
      expect(offers.first.id, 'mock_offer');
    });

    test(
      'falls back to mock repository when live API is enabled and endpoint is missing',
      () async {
        SharedPreferences.setMockInitialValues(<String, Object>{
          MarketplaceDevSettings.useLiveApiPreferenceKey: true,
        });
        final repository = createMarketplaceRepositoryForTesting(
          httpRepository: _FakeRepository(
            offersError: const MarketplaceRepositoryException(
              'missing',
              code: 'endpoint_not_available',
            ),
          ),
          mockRepository: _FakeRepository(offers: mockOffers),
          devSettings: const MarketplaceDevSettings(),
          mockMode: true,
        );

        final offers = await repository.fetchOffers();
        expect(offers.first.id, 'mock_offer');
      },
    );

    test('uses http repository when live API toggle is enabled', () async {
      SharedPreferences.setMockInitialValues(<String, Object>{
        MarketplaceDevSettings.useLiveApiPreferenceKey: true,
      });
      final repository = createMarketplaceRepositoryForTesting(
        httpRepository: _FakeRepository(offers: httpOffers),
        mockRepository: _FakeRepository(offers: mockOffers),
        devSettings: const MarketplaceDevSettings(),
        mockMode: true,
      );

      final offers = await repository.fetchOffers();
      expect(offers.first.id, 'http_offer');
    });
  });
}

Offer mockOffer(String id) {
  return Offer(
    id: id,
    title: id,
    vehicleClass: 'sedan',
    priceMinor: 1000,
    rating: 4.5,
    seatsAvailable: 4,
    etaMinutes: 5,
    highlights: const <String>['mock'],
  );
}

class _FakeRepository implements MarketplaceRepository {
  _FakeRepository({this.offers = const <Offer>[], this.offersError});

  final List<Offer> offers;
  final MarketplaceRepositoryException? offersError;

  @override
  Future<List<Offer>> fetchOffers() async {
    if (offersError != null) {
      throw offersError!;
    }
    return offers;
  }

  @override
  Future<PaywallCopy> fetchPaywallCopy(String offerId) async {
    return PaywallCopy(
      offerId: offerId,
      headline: 'headline',
      bullets: const <String>['a'],
      legalText: 'legal',
      ctaLabel: 'Continue',
      connectionFeeMinor: 100,
    );
  }

  @override
  Future<String> createCheckout(
    SeatSelection selection, {
    required String idempotencyKey,
  }) async {
    return 'purchase_1';
  }

  @override
  Future<String?> restorePurchaseByIdempotencyKey(String idempotencyKey) async {
    return 'purchase_1';
  }

  @override
  Future<List<TimelineEvent>> fetchTimeline(String purchaseId) async {
    return <TimelineEvent>[
      TimelineEvent(
        id: 'evt_1',
        title: 'Event',
        description: 'desc',
        occurredAt: DateTime.now().toUtc(),
        status: TimelineEventStatus.pending,
      ),
    ];
  }
}
