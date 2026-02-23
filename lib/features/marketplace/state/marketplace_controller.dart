import 'package:flutter/foundation.dart';

import '../data/marketplace_repository.dart';
import '../models/offer.dart';
import '../models/paywall_copy.dart';
import '../models/seat_selection.dart';
import '../models/timeline_event.dart';

class MarketplaceController extends ChangeNotifier {
  MarketplaceController({required MarketplaceRepository repository})
    : _repository = repository;

  final MarketplaceRepository _repository;

  List<Offer> _offers = <Offer>[];
  PaywallCopy? _paywallCopy;
  List<TimelineEvent> _timelineEvents = <TimelineEvent>[];
  String? _errorMessage;
  bool _loadingOffers = false;
  bool _loadingPaywall = false;
  bool _loadingTimeline = false;
  bool _submittingCheckout = false;
  int _seatCount = 1;
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
    try {
      final selection = SeatSelection(
        offerId: offerId,
        seatCount: _seatCount,
        assignments: _assignments.take(_seatCount).toList(growable: false),
      );
      return await _repository.createCheckout(selection);
    } catch (error) {
      _errorMessage = error.toString();
      return null;
    } finally {
      _submittingCheckout = false;
      notifyListeners();
    }
  }

  void clearError() {
    _errorMessage = null;
    notifyListeners();
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
