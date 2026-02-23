import 'dart:math';

import '../../../core/util/ids.dart';
import '../models/offer.dart';
import '../models/paywall_copy.dart';
import '../models/seat_selection.dart';
import '../models/timeline_event.dart';
import 'marketplace_repository.dart';

class MarketplaceRepositoryMock implements MarketplaceRepository {
  MarketplaceRepositoryMock({
    this.failFirstCreateCheckout = false,
    this.delayFirstRestore = false,
  });

  final bool failFirstCreateCheckout;
  final bool delayFirstRestore;
  final Map<String, List<TimelineEvent>> _timelineByPurchaseId =
      <String, List<TimelineEvent>>{};
  final Map<String, String> _purchaseIdByIdempotencyKey = <String, String>{};
  final Set<String> _failedCreateKeys = <String>{};
  final Set<String> _firstRestoreAttempted = <String>{};

  @override
  Future<List<Offer>> fetchOffers() async {
    await Future<void>.delayed(const Duration(milliseconds: 150));
    return _offers;
  }

  @override
  Future<PaywallCopy> fetchPaywallCopy(String offerId) async {
    await Future<void>.delayed(const Duration(milliseconds: 120));
    final copy = _paywallByOfferId[offerId];
    if (copy != null) {
      return copy;
    }
    throw const MarketplaceRepositoryException(
      'Could not find paywall terms for this offer.',
      code: 'offer_not_found',
    );
  }

  @override
  Future<String> createCheckout(
    SeatSelection selection, {
    required String idempotencyKey,
  }) async {
    await Future<void>.delayed(const Duration(milliseconds: 220));
    final existingPurchase = _purchaseIdByIdempotencyKey[idempotencyKey];
    if (existingPurchase != null && existingPurchase.isNotEmpty) {
      return existingPurchase;
    }

    final purchaseId = 'purchase_${newRequestId().replaceAll('-', '')}';
    _purchaseIdByIdempotencyKey[idempotencyKey] = purchaseId;
    _timelineByPurchaseId[purchaseId] = _buildTimeline(
      purchaseId: purchaseId,
      offerId: selection.offerId,
      seatCount: selection.seatCount,
      priceMinor: _priceForOffer(selection.offerId, selection.seatCount),
    );
    if (failFirstCreateCheckout &&
        !_failedCreateKeys.contains(idempotencyKey)) {
      _failedCreateKeys.add(idempotencyKey);
      throw const MarketplaceRepositoryException(
        'Transient checkout failure in mock mode.',
        code: 'checkout_temporary_unavailable',
      );
    }
    return purchaseId;
  }

  @override
  Future<String?> restorePurchaseByIdempotencyKey(String idempotencyKey) async {
    await Future<void>.delayed(const Duration(milliseconds: 140));
    final purchaseId = _purchaseIdByIdempotencyKey[idempotencyKey];
    if (purchaseId == null || purchaseId.isEmpty) {
      return null;
    }
    if (delayFirstRestore &&
        _failedCreateKeys.contains(idempotencyKey) &&
        !_firstRestoreAttempted.contains(idempotencyKey)) {
      _firstRestoreAttempted.add(idempotencyKey);
      return null;
    }
    return purchaseId;
  }

  @override
  Future<List<TimelineEvent>> fetchTimeline(String purchaseId) async {
    await Future<void>.delayed(const Duration(milliseconds: 130));
    final events = _timelineByPurchaseId[purchaseId];
    if (events != null) {
      return events;
    }

    return <TimelineEvent>[
      TimelineEvent(
        id: 'evt_${newRequestId()}',
        title: 'Marketplace request initialized',
        description:
            'We created a timeline shell for purchase id $purchaseId in mock mode.',
        occurredAt: DateTime.now().toUtc().subtract(const Duration(minutes: 1)),
        status: TimelineEventStatus.pending,
      ),
    ];
  }

  int _priceForOffer(String offerId, int seatCount) {
    final offer = _offers.firstWhere(
      (item) => item.id == offerId,
      orElse: () => _offers.first,
    );
    final multiplier = min(max(seatCount, 1), 50);
    return offer.priceMinor * multiplier;
  }

  List<TimelineEvent> _buildTimeline({
    required String purchaseId,
    required String offerId,
    required int seatCount,
    required int priceMinor,
  }) {
    final now = DateTime.now().toUtc();
    return <TimelineEvent>[
      TimelineEvent(
        id: 'evt_${newRequestId()}',
        title: 'Offer accepted',
        description: 'Offer $offerId accepted successfully.',
        occurredAt: now.subtract(const Duration(minutes: 4)),
        status: TimelineEventStatus.success,
      ),
      TimelineEvent(
        id: 'evt_${newRequestId()}',
        title: 'Connection fee verified',
        description: 'Connection fee gate passed.',
        occurredAt: now.subtract(const Duration(minutes: 3)),
        status: TimelineEventStatus.success,
      ),
      TimelineEvent(
        id: 'evt_${newRequestId()}',
        title: 'Seats locked',
        description:
            'Reserved $seatCount seat(s). Total booking amount: $priceMinor minor units.',
        occurredAt: now.subtract(const Duration(minutes: 2)),
        status: TimelineEventStatus.success,
      ),
      TimelineEvent(
        id: 'evt_${newRequestId()}',
        title: 'Purchase ready',
        description:
            'Purchase $purchaseId is waiting for final trip assignment.',
        occurredAt: now.subtract(const Duration(minutes: 1)),
        status: TimelineEventStatus.pending,
      ),
    ];
  }
}

final List<Offer> _offers = <Offer>[
  const Offer(
    id: 'offer_sedan_01',
    title: 'Budget Sedan',
    vehicleClass: 'sedan',
    priceMinor: 4200,
    rating: 4.5,
    seatsAvailable: 4,
    etaMinutes: 8,
    highlights: <String>[
      'Air conditioning',
      'Verified driver',
      'Cashless payment',
    ],
  ),
  const Offer(
    id: 'offer_suv_02',
    title: 'Comfort SUV',
    vehicleClass: 'suv',
    priceMinor: 5900,
    rating: 4.8,
    seatsAvailable: 6,
    etaMinutes: 6,
    highlights: <String>[
      'Large luggage space',
      'Premium interior',
      'Priority support',
    ],
  ),
  const Offer(
    id: 'offer_van_03',
    title: 'Family Van',
    vehicleClass: 'van',
    priceMinor: 7100,
    rating: 4.7,
    seatsAvailable: 8,
    etaMinutes: 12,
    highlights: <String>[
      'Group-friendly',
      'Accessible boarding',
      'Child seat options',
    ],
  ),
  const Offer(
    id: 'offer_exec_04',
    title: 'Executive Class',
    vehicleClass: 'executive',
    priceMinor: 9800,
    rating: 4.9,
    seatsAvailable: 3,
    etaMinutes: 5,
    highlights: <String>[
      'Top-rated chauffeur',
      'Quiet cabin',
      'On-time guarantee',
    ],
  ),
];

final Map<String, PaywallCopy> _paywallByOfferId = <String, PaywallCopy>{
  for (final offer in _offers)
    offer.id: PaywallCopy(
      offerId: offer.id,
      headline: 'Secure this ${offer.title} offer now',
      bullets: <String>[
        'Connection fee reserves your selected capacity instantly.',
        'Final routing and dispatch happen immediately after seat confirmation.',
        'Mock mode keeps your booking flow available even if backend endpoints are absent.',
      ],
      legalText:
          'By continuing, you agree to mock marketplace terms and ride matching policies.',
      ctaLabel: 'Continue to Seats',
      connectionFeeMinor: (offer.priceMinor * 0.1).round(),
    ),
};
