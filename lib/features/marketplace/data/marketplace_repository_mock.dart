import 'dart:math';

import '../../../core/util/ids.dart';
import '../models/billing_invoice.dart';
import '../models/offer.dart';
import '../models/org_summary.dart';
import '../models/paywall_copy.dart';
import '../models/payment_intent.dart';
import '../models/pricing_breakdown.dart';
import '../models/purchase_receipt.dart';
import '../models/purchase_snapshot.dart';
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
  final Map<String, String> _couponByOrgId = <String, String>{};
  final Map<String, String> _referralByOrgId = <String, String>{};
  final Map<String, List<BillingInvoice>> _invoicesByOrgId =
      <String, List<BillingInvoice>>{};
  final Map<String, MarketplaceInviteResult> _inviteByToken =
      <String, MarketplaceInviteResult>{};
  final List<MarketplaceOrgSummary> _orgs = <MarketplaceOrgSummary>[
    MarketplaceOrgSummary(
      id: _defaultOrgId,
      name: 'Demo Org',
      slug: 'demo-org',
      role: 'owner',
      memberStatus: 'active',
    ),
  ];

  static const String _defaultOrgId = 'org_demo';

  @override
  Future<PricingBreakdown> fetchPricingPreview({
    required String orgId,
    required String offerId,
    required int seats,
  }) async {
    await Future<void>.delayed(const Duration(milliseconds: 80));
    return _buildPricingBreakdown(orgId: orgId, offerId: offerId, seats: seats);
  }

  @override
  Future<PricingBreakdown> applyCoupon({
    required String orgId,
    required String couponCode,
    required String offerId,
    required int seats,
  }) async {
    await Future<void>.delayed(const Duration(milliseconds: 90));
    final normalized = couponCode.trim().toUpperCase();
    if (normalized.isEmpty ||
        !_couponDiscountMinorByCode.containsKey(normalized)) {
      throw const MarketplaceRepositoryException(
        'Coupon code is invalid.',
        code: 'INVALID_COUPON',
      );
    }
    _couponByOrgId[orgId] = normalized;
    return _buildPricingBreakdown(orgId: orgId, offerId: offerId, seats: seats);
  }

  @override
  Future<PricingBreakdown> removeCoupon({
    required String orgId,
    required String offerId,
    required int seats,
  }) async {
    await Future<void>.delayed(const Duration(milliseconds: 80));
    _couponByOrgId.remove(orgId);
    return _buildPricingBreakdown(orgId: orgId, offerId: offerId, seats: seats);
  }

  @override
  Future<PricingBreakdown> applyReferral({
    required String orgId,
    required String referralCode,
    required String offerId,
    required int seats,
  }) async {
    await Future<void>.delayed(const Duration(milliseconds: 90));
    final normalized = referralCode.trim().toUpperCase();
    if (normalized.isEmpty ||
        !_referralDiscountMinorByCode.containsKey(normalized)) {
      throw const MarketplaceRepositoryException(
        'Referral code is invalid.',
        code: 'INVALID_REFERRAL',
      );
    }
    _referralByOrgId[orgId] = normalized;
    return _buildPricingBreakdown(orgId: orgId, offerId: offerId, seats: seats);
  }

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
    _appendInvoice(
      orgId: _defaultOrgId,
      invoice: _newInvoice(
        orgId: _defaultOrgId,
        purchaseId: purchaseId,
        totalDueMinor: totalPrice,
        status: 'open',
      ),
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
  Future<MarketplacePaymentIntent?> createPaymentIntent({
    required String purchaseId,
  }) async {
    await Future<void>.delayed(const Duration(milliseconds: 120));
    final purchase = _purchaseById[purchaseId];
    return MarketplacePaymentIntent(
      id: 'pi_${newRequestId().replaceAll('-', '')}',
      purchaseId: purchaseId,
      status: 'pending',
      amountMinor: purchase?.totalPriceMinor ?? 0,
      currency: 'NGN',
      provider: 'manual',
    );
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
    _appendInvoice(
      orgId: _defaultOrgId,
      invoice: _newInvoice(
        orgId: _defaultOrgId,
        purchaseId: newPurchaseId,
        totalDueMinor: updated.totalPriceMinor,
        status: 'open',
      ),
    );
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

  @override
  Future<List<BillingInvoice>> fetchInvoices(String orgId) async {
    await Future<void>.delayed(const Duration(milliseconds: 90));
    return List<BillingInvoice>.from(
      _invoicesByOrgId[orgId] ?? const <BillingInvoice>[],
    );
  }

  @override
  Future<BillingInvoice?> retryInvoice({
    required String orgId,
    required String invoiceId,
  }) async {
    await Future<void>.delayed(const Duration(milliseconds: 120));
    final invoices = _invoicesByOrgId[orgId];
    if (invoices == null || invoices.isEmpty) {
      return null;
    }
    for (var index = 0; index < invoices.length; index++) {
      final invoice = invoices[index];
      if (invoice.invoiceId != invoiceId) {
        continue;
      }
      final updated = BillingInvoice(
        invoiceId: invoice.invoiceId,
        orgId: invoice.orgId,
        purchaseId: invoice.purchaseId,
        currency: invoice.currency,
        subtotalMinor: invoice.subtotalMinor,
        discountMinor: invoice.discountMinor,
        creditAppliedMinor: invoice.creditAppliedMinor,
        totalDueMinor: invoice.totalDueMinor,
        status: 'paid',
        createdAt: invoice.createdAt,
      );
      invoices[index] = updated;
      return updated;
    }
    return null;
  }

  @override
  Future<List<MarketplaceOrgSummary>> listOrgs() async {
    await Future<void>.delayed(const Duration(milliseconds: 60));
    return List<MarketplaceOrgSummary>.from(_orgs);
  }

  @override
  Future<List<MarketplacePurchaseSnapshot>> fetchOrgPurchases(
    String orgId,
  ) async {
    await Future<void>.delayed(const Duration(milliseconds: 60));
    return _purchaseById.values
        .map((receipt) {
          return MarketplacePurchaseSnapshot(
            purchaseId: receipt.purchaseId,
            offerId: receipt.offerId,
            seatCount: receipt.seatCount,
            status: receipt.status.toLowerCase(),
            createdAt: receipt.createdAt,
            totalAmount: receipt.totalPriceMinor,
            currency: 'NGN',
            version: 1,
            assignmentsVersion: 1,
            assignments: receipt.assignments
                .map(
                  (seat) => MarketplaceAssignment(
                    seatIndex: seat.seatNumber,
                    name: seat.name,
                    email: seat.email,
                  ),
                )
                .toList(growable: false),
            orgId: orgId,
            orgName: 'Demo Org',
            requesterRole: 'owner',
          );
        })
        .toList(growable: false);
  }

  @override
  Future<MarketplaceInviteResult> createOrgInvite({
    required String orgId,
    required String email,
    required String role,
  }) async {
    await Future<void>.delayed(const Duration(milliseconds: 80));
    final token = 'invite_${newRequestId().replaceAll('-', '')}';
    final invite = MarketplaceInviteResult(
      orgId: orgId,
      email: email,
      role: role,
      token: token,
    );
    _inviteByToken[token] = invite;
    return invite;
  }

  @override
  Future<MarketplaceOrgSummary?> acceptOrgInvite(String token) async {
    await Future<void>.delayed(const Duration(milliseconds: 80));
    final invite = _inviteByToken[token];
    if (invite == null) {
      return null;
    }
    final org = MarketplaceOrgSummary(
      id: invite.orgId,
      name: 'Org ${invite.orgId}',
      slug: invite.orgId.replaceAll('_', '-'),
      role: invite.role,
      memberStatus: 'active',
    );
    final index = _orgs.indexWhere((entry) => entry.id == org.id);
    if (index >= 0) {
      _orgs[index] = org;
    } else {
      _orgs.add(org);
    }
    return org;
  }

  Offer _findOffer(String offerId) {
    return _offers.firstWhere(
      (item) => item.id == offerId,
      orElse: () => _offers.first,
    );
  }

  PricingBreakdown _buildPricingBreakdown({
    required String orgId,
    required String offerId,
    required int seats,
  }) {
    final safeSeats = min(max(seats, 1), 50);
    final offer = _findOffer(offerId);
    final baseMinor = offer.priceMinor * safeSeats;
    final appliedCoupon = _couponByOrgId[orgId];
    final appliedReferral = _referralByOrgId[orgId];
    final couponDiscountMinor = (appliedCoupon != null)
        ? (_couponDiscountMinorByCode[appliedCoupon] ?? 0)
        : 0;
    final referralDiscountMinor = (appliedReferral != null)
        ? (_referralDiscountMinorByCode[appliedReferral] ?? 0)
        : 0;
    final discountTotal = couponDiscountMinor + referralDiscountMinor;
    final finalDueMinor = max(baseMinor - discountTotal, 0);

    return PricingBreakdown(
      orgId: orgId,
      offerId: offer.id,
      seats: safeSeats,
      currency: 'NGN',
      baseMinor: baseMinor,
      couponDiscountMinor: min(couponDiscountMinor, baseMinor),
      referralDiscountMinor: min(referralDiscountMinor, baseMinor),
      creditsAppliedMinor: 0,
      finalDueMinor: finalDueMinor,
      appliedCoupon: appliedCoupon,
      appliedReferral: appliedReferral,
    );
  }

  void _appendInvoice({
    required String orgId,
    required BillingInvoice invoice,
  }) {
    _invoicesByOrgId.putIfAbsent(orgId, () => <BillingInvoice>[]);
    _invoicesByOrgId[orgId]!.insert(0, invoice);
  }

  BillingInvoice _newInvoice({
    required String orgId,
    required String purchaseId,
    required int totalDueMinor,
    required String status,
  }) {
    return BillingInvoice(
      invoiceId: 'inv_${newRequestId().replaceAll('-', '')}',
      orgId: orgId,
      purchaseId: purchaseId,
      currency: 'NGN',
      subtotalMinor: totalDueMinor,
      discountMinor: 0,
      creditAppliedMinor: 0,
      totalDueMinor: totalDueMinor,
      status: status,
      createdAt: DateTime.now().toUtc(),
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

const Map<String, int> _couponDiscountMinorByCode = <String, int>{
  'SAVE500': 500,
  'LAUNCH50': 1500,
};

const Map<String, int> _referralDiscountMinorByCode = <String, int>{
  'REF250': 250,
  'REF500': 500,
};
