import 'dart:convert';

import 'package:flutter/foundation.dart';

import '../../../core/util/ids.dart';
import '../data/marketplace_local_store.dart';
import '../data/marketplace_repository.dart';
import '../models/offer.dart';
import '../models/paywall_copy.dart';
import '../models/seat_selection.dart';
import '../models/timeline_event.dart';

class MarketplaceController extends ChangeNotifier {
  MarketplaceController({
    required MarketplaceRepository repository,
    MarketplaceLocalStore? localStore,
  }) : _repository = repository,
       _localStore = localStore ?? const MarketplaceLocalStore();

  final MarketplaceRepository _repository;
  final MarketplaceLocalStore _localStore;

  List<Offer> _offers = <Offer>[];
  PaywallCopy? _paywallCopy;
  List<TimelineEvent> _timelineEvents = <TimelineEvent>[];
  String? _errorMessage;
  bool _loadingOffers = false;
  bool _loadingPaywall = false;
  bool _loadingTimeline = false;
  bool _submittingCheckout = false;
  int _seatCount = 1;
  String? _pendingCheckoutOfferId;
  String? _pendingCheckoutIdempotencyKey;
  List<SeatAssignment> _assignments = <SeatAssignment>[
    const SeatAssignment(seatNumber: 1, name: '', email: ''),
  ];

  List<Offer> get offers => _offers;
  PaywallCopy? get paywallCopy => _paywallCopy;
  List<TimelineEvent> get timelineEvents => _timelineEvents;
  String? get errorMessage => _errorMessage;
  bool get loadingOffers => _loadingOffers;
  bool get loadingPaywall => _loadingPaywall;
  bool get loadingTimeline => _loadingTimeline;
  bool get submittingCheckout => _submittingCheckout;
  int get seatCount => _seatCount;
  List<SeatAssignment> get assignments => _assignments;
  String? get pendingCheckoutIdempotencyKey => _pendingCheckoutIdempotencyKey;

  bool hasPendingCheckoutForOffer(String offerId) {
    return _pendingCheckoutOfferId == offerId &&
        _pendingCheckoutIdempotencyKey != null &&
        _pendingCheckoutIdempotencyKey!.isNotEmpty;
  }

  Future<void> loadOffers() async {
    if (_loadingOffers) {
      return;
    }
    _loadingOffers = true;
    _errorMessage = null;
    notifyListeners();
    try {
      _offers = await _repository.fetchOffers();
    } catch (error) {
      _errorMessage = error.toString();
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
    } catch (error) {
      _errorMessage = error.toString();
      _paywallCopy = null;
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
      _timelineEvents = await _repository.fetchTimeline(purchaseId);
    } catch (error) {
      _errorMessage = error.toString();
      _timelineEvents = <TimelineEvent>[];
    } finally {
      _loadingTimeline = false;
      notifyListeners();
    }
  }

  Future<void> loadPendingCheckoutForOffer(String offerId) async {
    String? pending;
    try {
      pending = await _localStore.readPendingCheckoutKeyForOffer(offerId);
    } catch (_) {
      pending = null;
    }
    _pendingCheckoutOfferId = offerId;
    _pendingCheckoutIdempotencyKey = pending;
    notifyListeners();
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
    final current = _assignments[index];
    _assignments[index] = current.copyWith(name: value.trim());
    notifyListeners();
  }

  void updateAssignmentEmail(int index, String value) {
    if (!_isValidAssignmentIndex(index)) {
      return;
    }
    final current = _assignments[index];
    _assignments[index] = current.copyWith(email: value.trim());
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
      await _finalizeCheckoutSuccess(
        offerId: offerId,
        idempotencyKey: idempotencyKey,
        purchaseId: purchaseId,
      );
      return purchaseId;
    } catch (error) {
      if (idempotencyKey != null && idempotencyKey.isNotEmpty) {
        final restored = await _tryRestoreCheckout(idempotencyKey);
        if (restored != null && restored.isNotEmpty) {
          await _finalizeCheckoutSuccess(
            offerId: offerId,
            idempotencyKey: idempotencyKey,
            purchaseId: restored,
          );
          return restored;
        }
      }
      _errorMessage = error.toString();
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
      return restored;
    } finally {
      _submittingCheckout = false;
      notifyListeners();
    }
  }

  void clearError() {
    _errorMessage = null;
    notifyListeners();
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
    } catch (_) {
      // Continue to local restoration map fallback.
    }
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
  }

  String _selectionSignature(SeatSelection selection) {
    final payload = <String, dynamic>{
      'offer_id': selection.offerId,
      'seat_count': selection.seatCount,
      'assignments': selection.assignments
          .map(
            (assignment) => <String, dynamic>{
              'seat_number': assignment.seatNumber,
              'name': assignment.name,
              'email': assignment.email,
            },
          )
          .toList(growable: false),
    };
    return jsonEncode(payload);
  }

  void _syncAssignmentsToSeatCount() {
    if (_assignments.length < _seatCount) {
      for (var index = _assignments.length + 1; index <= _seatCount; index++) {
        _assignments = <SeatAssignment>[
          ..._assignments,
          SeatAssignment(seatNumber: index, name: '', email: ''),
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
