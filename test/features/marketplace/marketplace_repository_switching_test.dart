import 'package:flutter_test/flutter_test.dart';
import 'package:hailo_core/features/marketplace/data/marketplace_dev_settings.dart';
import 'package:hailo_core/features/marketplace/data/marketplace_repository.dart';
import 'package:hailo_core/features/marketplace/models/offer.dart';
import 'package:hailo_core/features/marketplace/models/org_summary.dart';
import 'package:hailo_core/features/marketplace/models/paywall_copy.dart';
import 'package:hailo_core/features/marketplace/models/payment_intent.dart';
import 'package:hailo_core/features/marketplace/models/pricing_breakdown.dart';
import 'package:hailo_core/features/marketplace/models/purchase_receipt.dart';
import 'package:hailo_core/features/marketplace/models/purchase_snapshot.dart';
import 'package:hailo_core/features/marketplace/models/seat_selection.dart';
import 'package:hailo_core/features/marketplace/models/timeline_event.dart';
import 'package:hailo_core/features/marketplace/models/billing_invoice.dart';
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
      couponDiscountMinor: 100,
      referralDiscountMinor: 0,
      creditsAppliedMinor: 0,
      finalDueMinor: (seats * 1000) - 100,
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
      referralDiscountMinor: 100,
      creditsAppliedMinor: 0,
      finalDueMinor: (seats * 1000) - 100,
      appliedReferral: referralCode,
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
  Future<MarketplacePaymentIntent?> createPaymentIntent({
    required String purchaseId,
  }) async {
    return MarketplacePaymentIntent(
      id: 'pi_1',
      purchaseId: purchaseId,
      status: 'pending',
      amountMinor: 1000,
      currency: 'NGN',
      provider: 'manual',
    );
  }

  @override
  Future<String?> restorePurchaseByIdempotencyKey(String idempotencyKey) async {
    return 'purchase_1';
  }

  @override
  Future<PurchaseReceipt?> fetchPurchaseReceipt(String purchaseId) async {
    return PurchaseReceipt(
      purchaseId: purchaseId,
      offerId: 'offer_1',
      offerTitle: 'Offer',
      seatCount: 1,
      totalPriceMinor: 1000,
      status: 'CONFIRMED',
      createdAt: DateTime.now().toUtc(),
      assignments: const <SeatAssignment>[],
    );
  }

  @override
  Future<PurchaseReceipt> updateSeatCount({
    required String purchaseId,
    required int seatCount,
  }) async {
    return PurchaseReceipt(
      purchaseId: purchaseId,
      offerId: 'offer_1',
      offerTitle: 'Offer',
      seatCount: seatCount,
      totalPriceMinor: seatCount * 1000,
      status: 'SEATS_UPDATED',
      createdAt: DateTime.now().toUtc(),
      assignments: const <SeatAssignment>[],
    );
  }

  @override
  Future<PurchaseReceipt> updateAssignments({
    required String purchaseId,
    required List<SeatAssignment> assignments,
  }) async {
    return PurchaseReceipt(
      purchaseId: purchaseId,
      offerId: 'offer_1',
      offerTitle: 'Offer',
      seatCount: assignments.length,
      totalPriceMinor: assignments.length * 1000,
      status: 'ASSIGNMENT_UPDATED',
      createdAt: DateTime.now().toUtc(),
      assignments: assignments,
    );
  }

  @override
  Future<String> changePlan({
    required String purchaseId,
    required String newOfferId,
  }) async {
    return 'purchase_changed';
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

  @override
  Future<List<BillingInvoice>> fetchInvoices(String orgId) async {
    return <BillingInvoice>[
      BillingInvoice(
        invoiceId: 'inv_1',
        orgId: orgId,
        purchaseId: 'purchase_1',
        currency: 'NGN',
        subtotalMinor: 1000,
        discountMinor: 0,
        creditAppliedMinor: 0,
        totalDueMinor: 1000,
        status: 'open',
        createdAt: DateTime.now().toUtc(),
      ),
    ];
  }

  @override
  Future<BillingInvoice?> retryInvoice({
    required String orgId,
    required String invoiceId,
  }) async {
    return BillingInvoice(
      invoiceId: invoiceId,
      orgId: orgId,
      purchaseId: 'purchase_1',
      currency: 'NGN',
      subtotalMinor: 1000,
      discountMinor: 0,
      creditAppliedMinor: 0,
      totalDueMinor: 1000,
      status: 'paid',
      createdAt: DateTime.now().toUtc(),
    );
  }

  @override
  Future<List<MarketplaceOrgSummary>> listOrgs() async {
    return const <MarketplaceOrgSummary>[];
  }

  @override
  Future<List<MarketplacePurchaseSnapshot>> fetchOrgPurchases(
    String orgId,
  ) async {
    return const <MarketplacePurchaseSnapshot>[];
  }

  @override
  Future<MarketplaceInviteResult> createOrgInvite({
    required String orgId,
    required String email,
    required String role,
  }) async {
    return MarketplaceInviteResult(
      orgId: orgId,
      email: email,
      role: role,
      token: 'token',
    );
  }

  @override
  Future<MarketplaceOrgSummary?> acceptOrgInvite(String token) async {
    return null;
  }
}
