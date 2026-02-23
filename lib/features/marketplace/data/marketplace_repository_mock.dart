import 'dart:math';

import '../../../core/util/ids.dart';
import '../models/offer.dart';
import '../models/paywall_copy.dart';
import '../models/purchase_receipt.dart';
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
  final Map<String, PurchaseReceipt> _purchaseById =
      <String, PurchaseReceipt>{};
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
    final offer = _findOffer(selection.offerId);
    final seatCount = min(max(selection.seatCount, 1), 50);
    final assignments = _normalizeAssignments(
      provided: selection.assignments,
      seatCount: seatCount,
    );
    final totalPrice = offer.priceMinor * seatCount;

    _purchaseById[purchaseId] = PurchaseReceipt(
      purchaseId: purchaseId,
      offerId: offer.id,
      offerTitle: offer.title,
      seatCount: seatCount,
      totalPriceMinor: totalPrice,
      status: 'CONFIRMED',
      createdAt: DateTime.now().toUtc(),
      assignments: assignments,
    );
    _timelineByPurchaseId[purchaseId] = _buildTimeline(
      purchaseId: purchaseId,
      offerId: offer.id,
      seatCount: seatCount,
      priceMinor: totalPrice,
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
  Future<PurchaseReceipt?> fetchPurchaseReceipt(String purchaseId) async {
    await Future<void>.delayed(const Duration(milliseconds: 100));
    return _purchaseById[purchaseId];
  }

  @override
  Future<PurchaseReceipt> updateSeatCount({
    required String purchaseId,
    required int seatCount,
  }) async {
    await Future<void>.delayed(const Duration(milliseconds: 130));
    final existing = _purchaseById[purchaseId];
    if (existing == null) {
      throw const MarketplaceRepositoryException(
        'Could not find purchase to update seats.',
        code: 'purchase_not_found',
      );
    }

    final clampedSeatCount = min(max(seatCount, 1), 50);
    final offer = _findOffer(existing.offerId);
    final existingAssignments = existing.assignments;
    final updatedAssignments = <SeatAssignment>[];
    for (var index = 0; index < clampedSeatCount; index++) {
      if (index < existingAssignments.length) {
        final assignment = existingAssignments[index];
        updatedAssignments.add(assignment.copyWith(seatNumber: index + 1));
      } else {
        updatedAssignments.add(
          SeatAssignment(seatNumber: index + 1, name: '', email: ''),
        );
      }
    }

    final updated = existing.copyWith(
      seatCount: clampedSeatCount,
      totalPriceMinor: offer.priceMinor * clampedSeatCount,
      assignments: updatedAssignments,
      status: 'SEATS_UPDATED',
    );
    _purchaseById[purchaseId] = updated;

    _appendTimelineEvent(
      purchaseId: purchaseId,
      title: 'SEATS_UPDATED',
      description: 'Seat count adjusted to $clampedSeatCount.',
      status: TimelineEventStatus.success,
    );
    return updated;
  }

  @override
  Future<PurchaseReceipt> updateAssignments({
    required String purchaseId,
    required List<SeatAssignment> assignments,
  }) async {
    await Future<void>.delayed(const Duration(milliseconds: 130));
    final existing = _purchaseById[purchaseId];
    if (existing == null) {
      throw const MarketplaceRepositoryException(
        'Could not find purchase to update assignments.',
        code: 'purchase_not_found',
      );
    }

    final updatedAssignments = _normalizeAssignments(
      provided: assignments,
      seatCount: existing.seatCount,
    );
    final updated = existing.copyWith(
      assignments: updatedAssignments,
      status: 'ASSIGNMENT_UPDATED',
    );
    _purchaseById[purchaseId] = updated;
    _appendTimelineEvent(
      purchaseId: purchaseId,
      title: 'ASSIGNMENT_UPDATED',
      description: 'Passenger assignment details were updated.',
      status: TimelineEventStatus.pending,
    );
    return updated;
  }

  @override
  Future<String> changePlan({
    required String purchaseId,
    required String newOfferId,
  }) async {
    await Future<void>.delayed(const Duration(milliseconds: 180));
    final current = _purchaseById[purchaseId];
    if (current == null) {
      throw const MarketplaceRepositoryException(
        'Purchase not found for plan change.',
        code: 'purchase_not_found',
      );
    }
    final newOffer = _findOffer(newOfferId);
    final newPurchaseId = 'purchase_${newRequestId().replaceAll('-', '')}';
    final updated = current.copyWith(
      purchaseId: newPurchaseId,
      offerId: newOffer.id,
      offerTitle: newOffer.title,
      totalPriceMinor: newOffer.priceMinor * current.seatCount,
      status: 'PLAN_CHANGED',
      createdAt: DateTime.now().toUtc(),
    );
    _purchaseById[newPurchaseId] = updated;

    final previousEvents =
        _timelineByPurchaseId[purchaseId] ??
        <TimelineEvent>[
          TimelineEvent(
            id: 'evt_${newRequestId()}',
            title: 'Purchase initialized',
            description: 'Purchase $purchaseId created.',
            occurredAt: DateTime.now().toUtc(),
            status: TimelineEventStatus.pending,
          ),
        ];
    _timelineByPurchaseId[newPurchaseId] = <TimelineEvent>[
      ...previousEvents,
      TimelineEvent(
        id: 'evt_${newRequestId()}',
        title: 'PLAN_CHANGED',
        description:
            'Plan changed from ${current.offerTitle} to ${newOffer.title}.',
        occurredAt: DateTime.now().toUtc(),
        status: TimelineEventStatus.success,
      ),
    ];
    return newPurchaseId;
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

  Offer _findOffer(String offerId) {
    return _offers.firstWhere(
      (item) => item.id == offerId,
      orElse: () => _offers.first,
    );
  }

  List<SeatAssignment> _normalizeAssignments({
    required List<SeatAssignment> provided,
    required int seatCount,
  }) {
    final normalized = <SeatAssignment>[];
    for (var index = 0; index < seatCount; index++) {
      if (index < provided.length) {
        normalized.add(provided[index].copyWith(seatNumber: index + 1));
      } else {
        normalized.add(
          SeatAssignment(seatNumber: index + 1, name: '', email: ''),
        );
      }
    }
    return normalized;
  }

  void _appendTimelineEvent({
    required String purchaseId,
    required String title,
    required String description,
    required TimelineEventStatus status,
  }) {
    final existing = _timelineByPurchaseId[purchaseId] ?? <TimelineEvent>[];
    _timelineByPurchaseId[purchaseId] = <TimelineEvent>[
      ...existing,
      TimelineEvent(
        id: 'evt_${newRequestId()}',
        title: title,
        description: description,
        occurredAt: DateTime.now().toUtc(),
        status: status,
      ),
    ];
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
