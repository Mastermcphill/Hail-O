import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../../core/api/api_errors.dart';
import '../../../core/util/ids.dart';
import '../data/marketplace_local_store.dart';
import '../data/marketplace_repository.dart';
import '../models/billing_invoice.dart';
import '../models/offer.dart';
import '../models/org_summary.dart';
import '../models/outbox_item.dart';
import '../models/paywall_copy.dart';
import '../models/payment_intent.dart';
import '../models/pricing_breakdown.dart';
import '../models/purchase_receipt.dart';
import '../models/purchase_snapshot.dart';
import '../models/seat_selection.dart';
import '../models/timeline_event.dart';

class MarketplaceController extends ChangeNotifier {
  MarketplaceController({
    required MarketplaceRepository repository,
    MarketplaceLocalStore? localStore,
  }) : _repository = repository,
       _localStore = localStore ?? const MarketplaceLocalStore();

  static const String activeOrgPrefsKey = 'marketplace.active_org_id';

  final MarketplaceRepository _repository;
  final MarketplaceLocalStore _localStore;

  List<Offer> _offers = <Offer>[];
  PaywallCopy? _paywallCopy;
  List<TimelineEvent> _timelineEvents = <TimelineEvent>[];
  PricingBreakdown? _pricingBreakdown;
  List<BillingInvoice> _invoices = <BillingInvoice>[];
  List<MarketplaceOrgSummary> _orgs = <MarketplaceOrgSummary>[];
  List<MarketplacePurchaseSnapshot> _activeOrgPurchases =
      <MarketplacePurchaseSnapshot>[];
  PurchaseReceipt? _activeReceipt;
  MarketplacePaymentIntent? _activePaymentIntent;
  MarketplacePurchaseSnapshot? _purchase;

  String _activeOrgId = 'org_demo';
  String _couponDraft = '';
  String _referralDraft = '';
  String? _errorMessage;
  String? _infoBanner;
  int _seatCount = 1;
  int _pendingOutboxCount = 0;
  String? _pendingCheckoutOfferId;
  String? _pendingCheckoutIdempotencyKey;

  bool _loadingOffers = false;
  bool _loadingPaywall = false;
  bool _loadingTimeline = false;
  bool _loadingReceipt = false;
  bool _loadingPricing = false;
  bool _loadingInvoices = false;
  bool _loadingBilling = false;
  bool _loadingOrgs = false;
  bool _pricingActionInFlight = false;
  bool _retryingInvoice = false;
  bool _submittingCheckout = false;
  bool _updatingPurchase = false;
  bool _changingPlan = false;
  bool _riskLocked = false;
  bool _offlineMode = false;
  bool _isSyncing = false;
  bool _flushingOutbox = false;
  bool _disposed = false;

  Timer? _syncTimer;
  String? _syncPurchaseId;

  List<SeatAssignment> _assignments = <SeatAssignment>[
    const SeatAssignment(seatNumber: 1, name: '', email: ''),
  ];

  List<Offer> get offers => _offers;
  PaywallCopy? get paywallCopy => _paywallCopy;
  List<TimelineEvent> get timelineEvents => _timelineEvents;
  List<TimelineEvent> get timeline => _timelineEvents;
  PricingBreakdown? get pricingBreakdown => _pricingBreakdown;
  List<BillingInvoice> get invoices => _invoices;
  List<MarketplaceOrgSummary> get orgs => _orgs;
  List<MarketplacePurchaseSnapshot> get activeOrgPurchases =>
      _activeOrgPurchases;
  PurchaseReceipt? get activeReceipt => _activeReceipt;
  MarketplacePaymentIntent? get activePaymentIntent => _activePaymentIntent;
  MarketplacePurchaseSnapshot? get purchase => _purchase;

  bool get loadingOffers => _loadingOffers;
  bool get loadingPaywall => _loadingPaywall;
  bool get loadingTimeline => _loadingTimeline;
  bool get loadingReceipt => _loadingReceipt;
  bool get loadingPricing => _loadingPricing;
  bool get loadingInvoices => _loadingInvoices;
  bool get pricingActionInFlight => _pricingActionInFlight;
  bool get retryingInvoice => _retryingInvoice;
  bool get submittingCheckout => _submittingCheckout;
  bool get updatingPurchase => _updatingPurchase;
  bool get changingPlan => _changingPlan;
  bool get riskLocked => _riskLocked;
  bool get offlineMode => _offlineMode;
  bool get isSyncing => _isSyncing;
  bool get isLoadingOffers => _loadingOffers;
  bool get isLoadingBilling => _loadingBilling;
  int get pendingOutboxCount => _pendingOutboxCount;

  String? get errorMessage => _errorMessage;
  String? get infoBanner => _infoBanner ?? _errorMessage;
  String get activeOrgId => _activeOrgId;
  String get activeOrgRole => _activeOrg?.role ?? 'viewer';
  bool get canManageBilling {
    final role = activeOrgRole.toLowerCase();
    return role == 'owner' || role == 'admin' || role == 'billing';
  }

  bool get canManageOrgMembers {
    final role = activeOrgRole.toLowerCase();
    return role == 'owner' || role == 'admin';
  }

  String get couponDraft => _couponDraft;
  String get referralDraft => _referralDraft;
  int get seatCount => _seatCount;
  List<SeatAssignment> get assignments => _assignments;
  String? get pendingCheckoutIdempotencyKey => _pendingCheckoutIdempotencyKey;

  MarketplaceOrgSummary? get _activeOrg {
    for (final org in _orgs) {
      if (org.id == _activeOrgId) {
        return org;
      }
    }
    return null;
  }

  bool hasPendingCheckoutForOffer(String offerId) {
    return _pendingCheckoutOfferId == offerId &&
        _pendingCheckoutIdempotencyKey != null &&
        _pendingCheckoutIdempotencyKey!.isNotEmpty;
  }

  Future<void> initializeOffers() async {
    await loadOrgs();
    final cached = await _localStore.readOffers();
    if (cached.isNotEmpty) {
      _offers = cached;
      notifyListeners();
    }
    await loadOffers();
    await _refreshPendingOutboxCount();
  }

  Future<void> refreshOffers() async {
    await loadOffers();
  }

  Future<void> loadOffers() async {
    if (_loadingOffers) {
      return;
    }
    _loadingOffers = true;
    _errorMessage = null;
    notifyListeners();
    try {
      final offers = await _repository.fetchOffers();
      _offers = offers;
      _offlineMode = false;
      await _localStore.cacheOffers(offers);
    } catch (error) {
      _offlineMode = true;
      _errorMessage = error.toString();
      _offers = await _localStore.readOffers();
      if (_offers.isNotEmpty) {
        _infoBanner = 'Offline mode: using cached offers.';
      }
      _updateRiskLockFromError(error);
    } finally {
      _loadingOffers = false;
      notifyListeners();
    }
  }

  Future<void> loadPaywall(String offerId) async {
    if (_loadingPaywall) {
      return;
    }
    _loadingPaywall = true;
    _errorMessage = null;
    notifyListeners();
    try {
      _paywallCopy = await _repository.fetchPaywallCopy(offerId);
      await _hydratePricingAndInvoices(offerId);
      _offlineMode = false;
    } catch (error) {
      _errorMessage = error.toString();
      _paywallCopy = null;
      _offlineMode = true;
      _updateRiskLockFromError(error);
    } finally {
      _loadingPaywall = false;
      notifyListeners();
    }
  }

  Future<void> loadTimeline(String purchaseId) async {
    if (_loadingTimeline) {
      return;
    }
    _loadingTimeline = true;
    _errorMessage = null;
    notifyListeners();
    try {
      await refreshTimeline(purchaseId);
    } finally {
      _loadingTimeline = false;
      notifyListeners();
    }
  }

  Future<void> refreshTimeline(String purchaseId) async {
    try {
      final events = await _repository.fetchTimeline(purchaseId);
      final last = events.isNotEmpty ? events.last : null;
      await _localStore.mergeTimeline(
        purchaseId,
        events,
        latestEventAt: last?.timestamp?.toIso8601String(),
        cursor: last?.cursor,
      );
      _timelineEvents = await _localStore.readTimeline(purchaseId);
      _offlineMode = false;
    } catch (error) {
      _offlineMode = true;
      _errorMessage = error.toString();
      _timelineEvents = await _localStore.readTimeline(purchaseId);
    }
  }

  Future<void> loadPendingCheckoutForOffer(String offerId) async {
    _pendingCheckoutOfferId = offerId;
    _pendingCheckoutIdempotencyKey = await _localStore
        .readPendingCheckoutKeyForOffer(offerId);
    notifyListeners();
  }

  Future<void> loadPricingPreview(String offerId) async {
    if (_loadingPricing) {
      return;
    }
    _loadingPricing = true;
    _errorMessage = null;
    notifyListeners();
    try {
      _pricingBreakdown = await _repository.fetchPricingPreview(
        orgId: _activeOrgId,
        offerId: offerId,
        seats: _seatCount,
      );
      _offlineMode = false;
      _riskLocked = false;
    } catch (error) {
      _offlineMode = true;
      _errorMessage = error.toString();
      _updateRiskLockFromError(error);
    } finally {
      _loadingPricing = false;
      notifyListeners();
    }
  }

  Future<void> loadInvoices() async {
    if (_loadingInvoices) {
      return;
    }
    _loadingInvoices = true;
    _errorMessage = null;
    notifyListeners();
    try {
      _invoices = await _repository.fetchInvoices(_activeOrgId);
      _offlineMode = false;
    } catch (error) {
      _offlineMode = true;
      _errorMessage = error.toString();
      _invoices = <BillingInvoice>[];
      _updateRiskLockFromError(error);
    } finally {
      _loadingInvoices = false;
      notifyListeners();
    }
  }

  Future<void> applyCoupon({
    required String offerId,
    required String couponCode,
  }) async {
    if (_pricingActionInFlight) {
      return;
    }
    _pricingActionInFlight = true;
    _errorMessage = null;
    notifyListeners();
    try {
      _pricingBreakdown = await _repository.applyCoupon(
        orgId: _activeOrgId,
        couponCode: couponCode,
        offerId: offerId,
        seats: _seatCount,
      );
      _couponDraft = couponCode.trim();
      await _localStore.writeCouponCode(
        orgId: _activeOrgId,
        couponCode: _couponDraft,
      );
      _offlineMode = false;
      _riskLocked = false;
    } catch (error) {
      _offlineMode = true;
      _errorMessage = error.toString();
      _updateRiskLockFromError(error);
    } finally {
      _pricingActionInFlight = false;
      notifyListeners();
    }
  }

  Future<void> removeCoupon({required String offerId}) async {
    if (_pricingActionInFlight) {
      return;
    }
    _pricingActionInFlight = true;
    _errorMessage = null;
    notifyListeners();
    try {
      _pricingBreakdown = await _repository.removeCoupon(
        orgId: _activeOrgId,
        offerId: offerId,
        seats: _seatCount,
      );
      _couponDraft = '';
      await _localStore.clearCouponCode(_activeOrgId);
      _offlineMode = false;
      _riskLocked = false;
    } catch (error) {
      _offlineMode = true;
      _errorMessage = error.toString();
      _updateRiskLockFromError(error);
    } finally {
      _pricingActionInFlight = false;
      notifyListeners();
    }
  }

  Future<void> applyReferral({
    required String offerId,
    required String referralCode,
  }) async {
    if (_pricingActionInFlight) {
      return;
    }
    _pricingActionInFlight = true;
    _errorMessage = null;
    notifyListeners();
    try {
      _pricingBreakdown = await _repository.applyReferral(
        orgId: _activeOrgId,
        referralCode: referralCode,
        offerId: offerId,
        seats: _seatCount,
      );
      _referralDraft = referralCode.trim();
      await _localStore.writeReferralCode(
        orgId: _activeOrgId,
        referralCode: _referralDraft,
      );
      _offlineMode = false;
      _riskLocked = false;
    } catch (error) {
      _offlineMode = true;
      _errorMessage = error.toString();
      _updateRiskLockFromError(error);
    } finally {
      _pricingActionInFlight = false;
      notifyListeners();
    }
  }

  Future<BillingInvoice?> retryInvoice(String invoiceId) async {
    if (_retryingInvoice) {
      return null;
    }
    _retryingInvoice = true;
    _errorMessage = null;
    notifyListeners();
    try {
      final updated = await _repository.retryInvoice(
        orgId: _activeOrgId,
        invoiceId: invoiceId,
      );
      if (updated != null) {
        _upsertInvoice(updated);
      }
      _offlineMode = false;
      _riskLocked = false;
      return updated;
    } catch (error) {
      _offlineMode = true;
      _errorMessage = error.toString();
      _updateRiskLockFromError(error);
      return null;
    } finally {
      _retryingInvoice = false;
      notifyListeners();
    }
  }

  void setSeatCount(int value) {
    _seatCount = _clampSeatCount(value);
    _syncAssignmentsToSeatCount();
    notifyListeners();
  }

  void updateAssignmentName(int index, String value) {
    if (!_isValidAssignmentIndex(index)) {
      return;
    }
    _assignments[index] = _assignments[index].copyWith(name: value.trim());
    notifyListeners();
  }

  void updateAssignmentEmail(int index, String value) {
    if (!_isValidAssignmentIndex(index)) {
      return;
    }
    _assignments[index] = _assignments[index].copyWith(email: value.trim());
    notifyListeners();
  }

  Future<String?> createCheckout({required String offerId}) async {
    if (_submittingCheckout) {
      return null;
    }
    _submittingCheckout = true;
    _errorMessage = null;
    notifyListeners();
    final selection = SeatSelection(
      offerId: offerId,
      seatCount: _seatCount,
      assignments: _assignments.take(_seatCount).toList(growable: false),
    );
    String? idempotencyKey;
    try {
      idempotencyKey = await _resolveIdempotencyKey(
        offerId: offerId,
        selection: selection,
      );
      final purchaseId = await _repository.createCheckout(
        selection,
        idempotencyKey: idempotencyKey,
      );
      _setLocalReceiptFromSelection(
        selection: selection,
        purchaseId: purchaseId,
      );
      await _tryCreatePaymentIntent(purchaseId);
      await _finalizeCheckoutSuccess(
        offerId: offerId,
        idempotencyKey: idempotencyKey,
        purchaseId: purchaseId,
      );
      await _tryHydrateReceipt(purchaseId);
      _offlineMode = false;
      return purchaseId;
    } catch (error) {
      if (idempotencyKey != null) {
        final restored = await _tryRestoreCheckout(idempotencyKey);
        if (restored != null && restored.isNotEmpty) {
          await _tryCreatePaymentIntent(restored);
          await _finalizeCheckoutSuccess(
            offerId: offerId,
            idempotencyKey: idempotencyKey,
            purchaseId: restored,
          );
          await _tryHydrateReceipt(restored);
          return restored;
        }
      }
      _offlineMode = true;
      _errorMessage = error.toString();
      _updateRiskLockFromError(error);
      return null;
    } finally {
      _submittingCheckout = false;
      notifyListeners();
    }
  }

  Future<String?> resumePendingCheckout({required String offerId}) async {
    if (_submittingCheckout) {
      return null;
    }
    _submittingCheckout = true;
    _errorMessage = null;
    notifyListeners();
    try {
      final key = await _resolvePendingKeyForOffer(offerId);
      if (key == null || key.isEmpty) {
        _errorMessage = 'No pending purchase found to resume.';
        return null;
      }
      final restored = await _tryRestoreCheckout(key);
      if (restored == null || restored.isEmpty) {
        _errorMessage = 'Unable to resume purchase yet. Please retry.';
        return null;
      }
      await _finalizeCheckoutSuccess(
        offerId: offerId,
        idempotencyKey: key,
        purchaseId: restored,
      );
      await _tryCreatePaymentIntent(restored);
      await _tryHydrateReceipt(restored);
      return restored;
    } catch (error) {
      _offlineMode = true;
      _errorMessage = error.toString();
      _updateRiskLockFromError(error);
      return null;
    } finally {
      _submittingCheckout = false;
      notifyListeners();
    }
  }

  Future<String> submitSeats({
    required String offerId,
    required int seatCount,
    required List<MarketplaceAssignment> assignments,
  }) async {
    final normalized = _normalizeSeatAssignments(
      seatCount: _clampSeatCount(seatCount),
      assignments: assignments,
    );
    final selection = SeatSelection(
      offerId: offerId,
      seatCount: normalized.length,
      assignments: normalized,
    );
    final key = await _resolveIdempotencyKey(
      offerId: offerId,
      selection: selection,
    );
    try {
      final purchaseId = await _repository.createCheckout(
        selection,
        idempotencyKey: key,
      );
      await _tryCreatePaymentIntent(purchaseId);
      await _finalizeCheckoutSuccess(
        offerId: offerId,
        idempotencyKey: key,
        purchaseId: purchaseId,
      );
      await _localStore.deleteOutboxItem('create:$key');
      await _refreshPendingOutboxCount();
      _offlineMode = false;
      notifyListeners();
      return purchaseId;
    } catch (_) {
      final pendingPurchaseId = 'pending-$key';
      await enqueueOutbox(
        MarketplaceOutboxItem(
          id: 'create:$key',
          type: MarketplaceOutboxType.createPurchase,
          purchaseId: pendingPurchaseId,
          idempotencyKey: key,
          payload: <String, dynamic>{
            'offerId': offerId,
            'seatCount': normalized.length,
            'assignments': assignments
                .map((item) => item.toJson())
                .toList(growable: false),
          },
          baseVersion: 1,
          status: MarketplaceOutboxStatus.queued,
          attempts: 0,
          createdAt: DateTime.now().toUtc(),
        ),
      );
      _offlineMode = true;
      _infoBanner = 'Saved offline. Pending sync.';
      notifyListeners();
      return pendingPurchaseId;
    }
  }

  Future<void> enqueueOutbox(MarketplaceOutboxItem item) async {
    await _localStore.upsertOutboxItem(item);
    await _refreshPendingOutboxCount();
  }

  Future<void> flushOutbox() async {
    if (_flushingOutbox) {
      return;
    }
    _flushingOutbox = true;
    try {
      final due = await _localStore.readDueOutboxItems();
      for (final item in due) {
        await _processOutboxItem(item);
      }
    } finally {
      _flushingOutbox = false;
      await _refreshPendingOutboxCount();
      notifyListeners();
    }
  }

  Future<void> loadOrgs() async {
    if (_loadingOrgs) {
      return;
    }
    _loadingOrgs = true;
    _errorMessage = null;
    notifyListeners();
    try {
      final prefs = await SharedPreferences.getInstance();
      final preferred = prefs.getString(activeOrgPrefsKey);
      final loaded = await _repository.listOrgs();
      _orgs = loaded.isEmpty
          ? const <MarketplaceOrgSummary>[
              MarketplaceOrgSummary(
                id: 'org_demo',
                name: 'Personal Team',
                slug: 'personal-team',
                role: 'owner',
                memberStatus: 'active',
              ),
            ]
          : loaded;
      _activeOrgId = _resolveActiveOrgId(_orgs, preferredOrgId: preferred);
      await prefs.setString(activeOrgPrefsKey, _activeOrgId);
      _offlineMode = false;
    } catch (error) {
      _offlineMode = true;
      _errorMessage = error.toString();
      if (_orgs.isEmpty) {
        _orgs = const <MarketplaceOrgSummary>[
          MarketplaceOrgSummary(
            id: 'org_demo',
            name: 'Personal Team',
            slug: 'personal-team',
            role: 'owner',
            memberStatus: 'active',
          ),
        ];
      }
      _activeOrgId = _orgs.first.id;
    } finally {
      _loadingOrgs = false;
      notifyListeners();
    }
  }

  Future<void> selectOrg(String orgId) async {
    if (_orgs.where((org) => org.id == orgId).isEmpty) {
      return;
    }
    _activeOrgId = orgId;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(activeOrgPrefsKey, orgId);
    await refreshActiveOrgPurchases();
    await loadInvoices();
    notifyListeners();
  }

  Future<void> refreshActiveOrgPurchases() async {
    if (_loadingBilling) {
      return;
    }
    _loadingBilling = true;
    _errorMessage = null;
    notifyListeners();
    try {
      _activeOrgPurchases = await _repository.fetchOrgPurchases(_activeOrgId);
      _offlineMode = false;
    } catch (error) {
      _offlineMode = true;
      _errorMessage = error.toString();
      _activeOrgPurchases = <MarketplacePurchaseSnapshot>[];
    } finally {
      _loadingBilling = false;
      notifyListeners();
    }
  }

  Future<String?> createInvite({
    required String email,
    required String role,
  }) async {
    if (!canManageOrgMembers) {
      _infoBanner = "You don't have billing permission";
      notifyListeners();
      return null;
    }
    final invite = await _repository.createOrgInvite(
      orgId: _activeOrgId,
      email: email,
      role: role,
    );
    _infoBanner = null;
    notifyListeners();
    return invite.token;
  }

  Future<void> acceptInvite(String token) async {
    final org = await _repository.acceptOrgInvite(token);
    if (org == null) {
      _infoBanner = 'Invite not found.';
      notifyListeners();
      return;
    }
    final idx = _orgs.indexWhere((entry) => entry.id == org.id);
    if (idx >= 0) {
      _orgs[idx] = org;
    } else {
      _orgs = <MarketplaceOrgSummary>[..._orgs, org];
    }
    await selectOrg(org.id);
    _infoBanner = null;
    notifyListeners();
  }

  Future<String> resolvePurchaseId(String purchaseId) async {
    final trimmed = purchaseId.trim();
    if (!trimmed.startsWith('pending-')) {
      return trimmed;
    }
    final key = trimmed.substring('pending-'.length);
    final restored = await _tryRestoreCheckout(key);
    return restored ?? trimmed;
  }

  Future<void> loadPurchase(String purchaseId) async {
    final resolved = await resolvePurchaseId(purchaseId);
    await loadPurchaseReceipt(resolved);
    await refreshTimeline(resolved);
  }

  Future<void> startSyncLoop({String? purchaseId}) async {
    if (purchaseId != null && purchaseId.trim().isNotEmpty) {
      _syncPurchaseId = purchaseId.trim();
    }
    if (_syncTimer != null) {
      return;
    }
    _isSyncing = true;
    notifyListeners();
    _syncTimer = Timer.periodic(const Duration(seconds: 5), (_) async {
      await flushOutbox();
      final tracked = _syncPurchaseId;
      if (tracked != null && tracked.isNotEmpty) {
        final resolved = await resolvePurchaseId(tracked);
        _syncPurchaseId = resolved;
        await refreshTimeline(resolved);
      }
    });
  }

  void stopSyncLoop() {
    if (_disposed) {
      return;
    }
    _syncTimer?.cancel();
    _syncTimer = null;
    _syncPurchaseId = null;
    _isSyncing = false;
    notifyListeners();
  }

  Future<PurchaseReceipt?> loadPurchaseReceipt(String purchaseId) async {
    if (_loadingReceipt) {
      return _activeReceipt;
    }
    _loadingReceipt = true;
    _errorMessage = null;
    notifyListeners();
    try {
      final receipt = await _repository.fetchPurchaseReceipt(purchaseId);
      _activeReceipt = receipt;
      if (receipt != null) {
        _seatCount = _clampSeatCount(receipt.seatCount);
        _assignments = receipt.assignments.isEmpty
            ? <SeatAssignment>[
                const SeatAssignment(seatNumber: 1, name: '', email: ''),
              ]
            : receipt.assignments;
        _syncAssignmentsToSeatCount();
        _purchase = _snapshotFromReceipt(receipt);
        await _localStore.cachePurchase(_purchase!);
      } else {
        _purchase = await _localStore.readPurchase(purchaseId);
      }
      _offlineMode = false;
      return receipt;
    } catch (error) {
      _offlineMode = true;
      _errorMessage = error.toString();
      _purchase = await _localStore.readPurchase(purchaseId);
      _updateRiskLockFromError(error);
      return null;
    } finally {
      _loadingReceipt = false;
      notifyListeners();
    }
  }

  Future<PurchaseReceipt?> updatePurchaseSeatCount({
    required String purchaseId,
    required int seatCount,
  }) async {
    if (_updatingPurchase) {
      return null;
    }
    _updatingPurchase = true;
    _errorMessage = null;
    notifyListeners();
    try {
      final updated = await _repository.updateSeatCount(
        purchaseId: purchaseId,
        seatCount: seatCount,
      );
      _activeReceipt = updated;
      _seatCount = _clampSeatCount(updated.seatCount);
      _assignments = updated.assignments;
      _syncAssignmentsToSeatCount();
      _purchase = _snapshotFromReceipt(updated);
      await _localStore.cachePurchase(_purchase!);
      await loadTimeline(purchaseId);
      return updated;
    } catch (error) {
      _errorMessage = error.toString();
      _updateRiskLockFromError(error);
      return null;
    } finally {
      _updatingPurchase = false;
      notifyListeners();
    }
  }

  Future<PurchaseReceipt?> updatePurchaseAssignments({
    required String purchaseId,
  }) async {
    if (_updatingPurchase) {
      return null;
    }
    _updatingPurchase = true;
    _errorMessage = null;
    notifyListeners();
    try {
      final updated = await _repository.updateAssignments(
        purchaseId: purchaseId,
        assignments: _assignments.take(_seatCount).toList(growable: false),
      );
      _activeReceipt = updated;
      _assignments = updated.assignments;
      _syncAssignmentsToSeatCount();
      _purchase = _snapshotFromReceipt(updated);
      await _localStore.cachePurchase(_purchase!);
      await loadTimeline(purchaseId);
      return updated;
    } catch (error) {
      _errorMessage = error.toString();
      _updateRiskLockFromError(error);
      return null;
    } finally {
      _updatingPurchase = false;
      notifyListeners();
    }
  }

  Future<String?> changePlan({
    required String purchaseId,
    required String newOfferId,
  }) async {
    if (_changingPlan) {
      return null;
    }
    _changingPlan = true;
    _errorMessage = null;
    notifyListeners();
    try {
      final newPurchaseId = await _repository.changePlan(
        purchaseId: purchaseId,
        newOfferId: newOfferId,
      );
      await loadPurchaseReceipt(newPurchaseId);
      await loadTimeline(newPurchaseId);
      return newPurchaseId;
    } catch (error) {
      _errorMessage = error.toString();
      _updateRiskLockFromError(error);
      return null;
    } finally {
      _changingPlan = false;
      notifyListeners();
    }
  }

  Offer? offerById(String offerId) {
    for (final offer in _offers) {
      if (offer.id == offerId) {
        return offer;
      }
    }
    return null;
  }

  void clearError() {
    _errorMessage = null;
    _infoBanner = null;
    notifyListeners();
  }

  Future<PurchaseReceipt?> refreshPurchaseStatus(String purchaseId) async {
    try {
      final receipt = await _repository.fetchPurchaseReceipt(purchaseId);
      if (receipt == null) {
        return null;
      }
      _activeReceipt = receipt;
      if (_activePaymentIntent != null &&
          _activePaymentIntent!.purchaseId != receipt.purchaseId) {
        _activePaymentIntent = null;
      }
      _seatCount = _clampSeatCount(receipt.seatCount);
      _assignments = receipt.assignments.isEmpty
          ? <SeatAssignment>[
              const SeatAssignment(seatNumber: 1, name: '', email: ''),
            ]
          : receipt.assignments;
      _syncAssignmentsToSeatCount();
      _purchase = _snapshotFromReceipt(receipt);
      await _localStore.cachePurchase(_purchase!);
      _offlineMode = false;
      notifyListeners();
      return receipt;
    } catch (_) {
      return null;
    }
  }

  void updateCouponDraft(String value) {
    _couponDraft = value.trim();
    notifyListeners();
  }

  void updateReferralDraft(String value) {
    _referralDraft = value.trim();
    notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    _syncTimer?.cancel();
    _localStore.close();
    super.dispose();
  }

  Future<void> _processOutboxItem(MarketplaceOutboxItem item) async {
    try {
      if (item.type == MarketplaceOutboxType.createPurchase) {
        final offerId = (item.payload['offerId'] ?? '').toString();
        final seatCount = _parseInt(item.payload['seatCount'], fallback: 1);
        final rows =
            (item.payload['assignments'] as List<dynamic>? ?? const <dynamic>[])
                .whereType<Map>()
                .map(
                  (entry) => MarketplaceAssignment.fromJson(
                    entry.map(
                      (key, value) =>
                          MapEntry<String, dynamic>(key.toString(), value),
                    ),
                  ),
                )
                .toList(growable: false);
        final selection = SeatSelection(
          offerId: offerId,
          seatCount: seatCount,
          assignments: _normalizeSeatAssignments(
            seatCount: seatCount,
            assignments: rows,
          ),
        );
        final purchaseId = await _repository.createCheckout(
          selection,
          idempotencyKey: item.idempotencyKey,
        );
        await _finalizeCheckoutSuccess(
          offerId: offerId,
          idempotencyKey: item.idempotencyKey,
          purchaseId: purchaseId,
        );
        await _localStore.deleteOutboxItem(item.id);
        _infoBanner = null;
        return;
      }
      if (item.type == MarketplaceOutboxType.updateSeats) {
        final purchaseId = item.purchaseId ?? '';
        final seatCount = _parseInt(item.payload['seatCount'], fallback: 1);
        final updated = await _repository.updateSeatCount(
          purchaseId: purchaseId,
          seatCount: seatCount,
        );
        _activeReceipt = updated;
        _purchase = _snapshotFromReceipt(updated);
        await _localStore.cachePurchase(_purchase!);
        await _localStore.deleteOutboxItem(item.id);
        _infoBanner = null;
        return;
      }
      if (item.type == MarketplaceOutboxType.updateAssignments) {
        final purchaseId = item.purchaseId ?? '';
        final rows =
            (item.payload['assignments'] as List<dynamic>? ?? const <dynamic>[])
                .whereType<Map>()
                .map(
                  (entry) => SeatAssignment(
                    seatNumber: _parseInt(
                      entry['seat_number'],
                      fallback: _parseInt(entry['seatNumber'], fallback: 1),
                    ),
                    name: (entry['name'] ?? '').toString(),
                    email: (entry['email'] ?? '').toString(),
                  ),
                )
                .toList(growable: false);
        final updated = await _repository.updateAssignments(
          purchaseId: purchaseId,
          assignments: rows,
        );
        _activeReceipt = updated;
        _purchase = _snapshotFromReceipt(updated);
        await _localStore.cachePurchase(_purchase!);
        await _localStore.deleteOutboxItem(item.id);
        _infoBanner = null;
        return;
      }
      if (item.type == MarketplaceOutboxType.changePlan) {
        final purchaseId = item.purchaseId ?? '';
        final newOfferId = (item.payload['newOfferId'] ?? '').toString();
        await _repository.changePlan(
          purchaseId: purchaseId,
          newOfferId: newOfferId,
        );
        await _localStore.deleteOutboxItem(item.id);
        _infoBanner = null;
      }
    } on ApiException catch (error) {
      if (_isVersionConflict(error)) {
        await _localStore.updateOutboxStatus(
          id: item.id,
          status: MarketplaceOutboxStatus.queued,
          attempts: item.attempts,
          nextRetryAt: null,
          baseVersion: _extractLatestVersion(error) ?? item.baseVersion,
          lastError: null,
        );
        return;
      }
      await _markOutboxFailure(item, error.toString());
    } catch (error) {
      await _markOutboxFailure(item, error.toString());
    }
  }

  Future<void> _markOutboxFailure(
    MarketplaceOutboxItem item,
    String message,
  ) async {
    final attempts = item.attempts + 1;
    await _localStore.updateOutboxStatus(
      id: item.id,
      status: MarketplaceOutboxStatus.failed,
      attempts: attempts,
      nextRetryAt: DateTime.now().toUtc().add(_retryDelay(attempts)),
      lastError: message,
      baseVersion: item.baseVersion,
    );
    _offlineMode = true;
    _infoBanner = 'Offline mode: pending changes will retry automatically.';
  }

  Duration _retryDelay(int attempts) {
    if (attempts <= 1) {
      return const Duration(seconds: 15);
    }
    if (attempts == 2) {
      return const Duration(minutes: 1);
    }
    if (attempts == 3) {
      return const Duration(minutes: 5);
    }
    return const Duration(minutes: 15);
  }

  bool _isVersionConflict(ApiException error) {
    final code = (error.code ?? '').toUpperCase();
    return error.statusCode == 409 || code == 'VERSION_CONFLICT';
  }

  int? _extractLatestVersion(ApiException error) {
    final envelope = error.envelope;
    if (envelope == null) {
      return null;
    }
    final data = envelope['data'];
    if (data is! Map) {
      return null;
    }
    final latest = data['latest'];
    if (latest is! Map) {
      return null;
    }
    return _parseInt(latest['version']);
  }

  Future<void> _refreshPendingOutboxCount() async {
    final all = await _localStore.readAllOutboxItems();
    _pendingOutboxCount = all
        .where(
          (item) =>
              item.status == MarketplaceOutboxStatus.queued ||
              item.status == MarketplaceOutboxStatus.failed,
        )
        .length;
  }

  Future<void> _hydratePricingAndInvoices(String offerId) async {
    _couponDraft = await _localStore.readCouponCode(_activeOrgId) ?? '';
    _referralDraft = await _localStore.readReferralCode(_activeOrgId) ?? '';
    try {
      _pricingBreakdown = await _repository.fetchPricingPreview(
        orgId: _activeOrgId,
        offerId: offerId,
        seats: _seatCount,
      );
    } catch (_) {}
    try {
      _invoices = await _repository.fetchInvoices(_activeOrgId);
    } catch (_) {
      _invoices = <BillingInvoice>[];
    }
  }

  Future<String> _resolveIdempotencyKey({
    required String offerId,
    required SeatSelection selection,
  }) async {
    final signature = _selectionSignature(selection);
    final bySignature = await _localStore.readCheckoutIdempotencyKey(signature);
    final byOffer = await _resolvePendingKeyForOffer(offerId);
    final resolved = (bySignature != null && bySignature.isNotEmpty)
        ? bySignature
        : ((byOffer != null && byOffer.isNotEmpty)
              ? byOffer
              : newIdempotencyKey());
    await _localStore.writeCheckoutIdempotencyKey(
      signature: signature,
      idempotencyKey: resolved,
    );
    await _localStore.writePendingCheckoutKeyForOffer(
      offerId: offerId,
      idempotencyKey: resolved,
    );
    _pendingCheckoutOfferId = offerId;
    _pendingCheckoutIdempotencyKey = resolved;
    return resolved;
  }

  Future<String?> _resolvePendingKeyForOffer(String offerId) async {
    if (_pendingCheckoutOfferId == offerId &&
        _pendingCheckoutIdempotencyKey != null &&
        _pendingCheckoutIdempotencyKey!.isNotEmpty) {
      return _pendingCheckoutIdempotencyKey;
    }
    final fromStore = await _localStore.readPendingCheckoutKeyForOffer(offerId);
    _pendingCheckoutOfferId = offerId;
    _pendingCheckoutIdempotencyKey = fromStore;
    return fromStore;
  }

  Future<String?> _tryRestoreCheckout(String idempotencyKey) async {
    try {
      final restored = await _repository.restorePurchaseByIdempotencyKey(
        idempotencyKey,
      );
      if (restored != null && restored.isNotEmpty) {
        return restored;
      }
    } catch (_) {}
    return _localStore.readPurchaseIdByIdempotencyKey(idempotencyKey);
  }

  Future<void> _finalizeCheckoutSuccess({
    required String offerId,
    required String idempotencyKey,
    required String purchaseId,
  }) async {
    await _localStore.writePurchaseIdByIdempotencyKey(
      idempotencyKey: idempotencyKey,
      purchaseId: purchaseId,
    );
    await _localStore.clearPendingCheckoutKeyForOffer(offerId);
    _pendingCheckoutOfferId = offerId;
    _pendingCheckoutIdempotencyKey = null;
    _errorMessage = null;
    if (_activePaymentIntent == null ||
        _activePaymentIntent!.purchaseId != purchaseId) {
      _infoBanner = null;
    }
  }

  void _setLocalReceiptFromSelection({
    required SeatSelection selection,
    required String purchaseId,
  }) {
    final offer = offerById(selection.offerId);
    final offerTitle = offer?.title ?? selection.offerId;
    final basePrice = offer?.priceMinor ?? 0;
    _activeReceipt = PurchaseReceipt(
      purchaseId: purchaseId,
      offerId: selection.offerId,
      offerTitle: offerTitle,
      seatCount: selection.seatCount,
      totalPriceMinor: basePrice * selection.seatCount,
      status: 'PENDING_PAYMENT',
      createdAt: DateTime.now().toUtc(),
      assignments: selection.assignments,
    );
    _purchase = _snapshotFromReceipt(_activeReceipt!);
  }

  Future<void> _tryHydrateReceipt(String purchaseId) async {
    try {
      final receipt = await _repository.fetchPurchaseReceipt(purchaseId);
      if (receipt != null) {
        _activeReceipt = receipt;
        if (_activePaymentIntent != null &&
            _activePaymentIntent!.purchaseId != receipt.purchaseId) {
          _activePaymentIntent = null;
        }
        _seatCount = _clampSeatCount(receipt.seatCount);
        _assignments = receipt.assignments;
        _syncAssignmentsToSeatCount();
        _purchase = _snapshotFromReceipt(receipt);
        await _localStore.cachePurchase(_purchase!);
      }
    } catch (_) {}
  }

  Future<void> _tryCreatePaymentIntent(String purchaseId) async {
    try {
      final intent = await _repository.createPaymentIntent(
        purchaseId: purchaseId,
        idempotencyKey: newIdempotencyKey(),
      );
      if (intent == null) {
        return;
      }
      _activePaymentIntent = intent;
      if (intent.isPending) {
        _infoBanner = 'Pending payment';
      }
    } catch (error) {
      _infoBanner =
          'Purchase created. Payment intent is pending initialization.';
      _errorMessage = error.toString();
    }
  }

  void _upsertInvoice(BillingInvoice invoice) {
    final idx = _invoices.indexWhere(
      (entry) => entry.invoiceId == invoice.invoiceId,
    );
    if (idx < 0) {
      _invoices = <BillingInvoice>[invoice, ..._invoices];
    } else {
      _invoices[idx] = invoice;
      _invoices = List<BillingInvoice>.from(_invoices);
    }
  }

  String _selectionSignature(SeatSelection selection) {
    return jsonEncode(<String, dynamic>{
      'offer_id': selection.offerId,
      'seat_count': selection.seatCount,
      'assignments': selection.assignments
          .map((entry) => entry.toMap())
          .toList(growable: false),
    });
  }

  void _syncAssignmentsToSeatCount() {
    if (_assignments.length < _seatCount) {
      for (var i = _assignments.length + 1; i <= _seatCount; i++) {
        _assignments = <SeatAssignment>[
          ..._assignments,
          SeatAssignment(seatNumber: i, name: '', email: ''),
        ];
      }
      return;
    }
    if (_assignments.length > _seatCount) {
      _assignments = _assignments.take(_seatCount).toList(growable: false);
    }
  }

  bool _isValidAssignmentIndex(int index) {
    return index >= 0 && index < _assignments.length;
  }

  void _updateRiskLockFromError(Object error) {
    _riskLocked = error.toString().toLowerCase().contains('risk_locked');
  }

  String _resolveActiveOrgId(
    List<MarketplaceOrgSummary> orgs, {
    required String? preferredOrgId,
  }) {
    if (preferredOrgId != null && preferredOrgId.trim().isNotEmpty) {
      for (final org in orgs) {
        if (org.id == preferredOrgId) {
          return preferredOrgId;
        }
      }
    }
    return orgs.isEmpty ? 'org_demo' : orgs.first.id;
  }

  List<SeatAssignment> _normalizeSeatAssignments({
    required int seatCount,
    required List<MarketplaceAssignment> assignments,
  }) {
    final rows = <SeatAssignment>[];
    for (var i = 0; i < seatCount; i++) {
      final source = i < assignments.length ? assignments[i] : null;
      rows.add(
        SeatAssignment(
          seatNumber: i + 1,
          name: source?.name ?? '',
          email: source?.email ?? '',
        ),
      );
    }
    return rows;
  }

  MarketplacePurchaseSnapshot _snapshotFromReceipt(PurchaseReceipt receipt) {
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
            (item) => MarketplaceAssignment(
              seatIndex: item.seatNumber,
              name: item.name,
              email: item.email,
            ),
          )
          .toList(growable: false),
      orgId: _activeOrgId,
      orgName: _activeOrg?.name,
      requesterRole: activeOrgRole,
    );
  }
}

int _parseInt(Object? value, {int fallback = 0}) {
  if (value is num) {
    return value.toInt();
  }
  if (value is String) {
    return int.tryParse(value.trim()) ?? fallback;
  }
  return fallback;
}

int _clampSeatCount(int value) {
  if (value < 1) {
    return 1;
  }
  if (value > 50) {
    return 50;
  }
  return value;
}
