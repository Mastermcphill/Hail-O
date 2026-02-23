import 'package:uuid/uuid.dart';

import 'marketplace_repository.dart';

class InMemoryMarketplaceRepository implements MarketplaceRepository {
  InMemoryMarketplaceRepository({Uuid? uuid})
    : _uuid = uuid ?? const Uuid(),
      _offers = <String, Map<String, Object?>>{
        'starter_monthly': <String, Object?>{
          'id': 'starter_monthly',
          'title': 'Starter Monthly',
          'description': 'Core marketplace access',
          'currency': 'NGN',
          'price_minor': 150000,
          'interval': 'month',
          'features_json': const <String>['Basic analytics', 'Email support'],
          'seat_policy_json': const <String, Object?>{
            'min': 1,
            'max': 5,
            'included': 1,
          },
          'is_active': true,
          'sort_rank': 10,
          'created_at': DateTime.utc(2026, 1, 1),
          'updated_at': DateTime.utc(2026, 1, 1),
        },
        'pro_monthly': <String, Object?>{
          'id': 'pro_monthly',
          'title': 'Pro Monthly',
          'description': 'Advanced marketplace controls',
          'currency': 'NGN',
          'price_minor': 350000,
          'interval': 'month',
          'features_json': const <String>[
            'Priority matching',
            'Seat management',
          ],
          'seat_policy_json': const <String, Object?>{
            'min': 1,
            'max': 20,
            'included': 5,
          },
          'is_active': true,
          'sort_rank': 20,
          'created_at': DateTime.utc(2026, 1, 1),
          'updated_at': DateTime.utc(2026, 1, 1),
        },
        'business_yearly': <String, Object?>{
          'id': 'business_yearly',
          'title': 'Business Yearly',
          'description': 'Enterprise automation toolkit',
          'currency': 'NGN',
          'price_minor': 3600000,
          'interval': 'year',
          'features_json': const <String>[
            'Dedicated support',
            'Advanced reporting',
          ],
          'seat_policy_json': const <String, Object?>{
            'min': 5,
            'max': 50,
            'included': 20,
          },
          'is_active': true,
          'sort_rank': 30,
          'created_at': DateTime.utc(2026, 1, 1),
          'updated_at': DateTime.utc(2026, 1, 1),
        },
      };

  final Uuid _uuid;
  final Map<String, Map<String, Object?>> _offers;
  final Map<String, Map<String, Object?>> _purchases =
      <String, Map<String, Object?>>{};
  final Map<String, String> _idempotencyLookup = <String, String>{};
  final Map<String, List<Map<String, Object?>>> _assignments =
      <String, List<Map<String, Object?>>>{};
  final Map<String, List<Map<String, Object?>>> _timeline =
      <String, List<Map<String, Object?>>>{};
  final Map<String, Map<String, Object?>> _webhooks =
      <String, Map<String, Object?>>{};

  @override
  Future<List<Map<String, Object?>>> listOffers() async {
    final offers = _offers.values
        .where((offer) => offer['is_active'] == true)
        .map((offer) => Map<String, Object?>.from(offer))
        .toList(growable: false);
    offers.sort(
      (a, b) => ((a['sort_rank'] as num?)?.toInt() ?? 0).compareTo(
        (b['sort_rank'] as num?)?.toInt() ?? 0,
      ),
    );
    return offers;
  }

  @override
  Future<Map<String, Object?>?> findOfferById(String offerId) async {
    final offer = _offers[offerId];
    return offer == null ? null : Map<String, Object?>.from(offer);
  }

  @override
  Future<Map<String, Object?>> createOrReusePurchase({
    required String userId,
    required String offerId,
    required int seatCount,
    required String idempotencyKey,
    required String provider,
    List<Map<String, Object?>> assignments = const <Map<String, Object?>>[],
  }) async {
    final offer = _offers[offerId];
    if (offer == null) {
      throw StateError('offer_not_found');
    }
    final replayKey = '$userId|$idempotencyKey';
    final existingPurchaseId = _idempotencyLookup[replayKey];
    if (existingPurchaseId != null) {
      final replayed = _purchases[existingPurchaseId];
      if (replayed == null) {
        throw StateError('purchase_replay_missing');
      }
      return <String, Object?>{...replayed, '_replayed': true};
    }
    final nowUtc = DateTime.now().toUtc();
    final purchaseId = _uuid.v4();
    final purchase = <String, Object?>{
      'id': purchaseId,
      'user_id': userId,
      'offer_id': offerId,
      'status': 'pending',
      'currency': offer['currency'] as String? ?? 'NGN',
      'price_minor': (offer['price_minor'] as num?)?.toInt() ?? 0,
      'seats_total': seatCount,
      'provider': provider,
      'provider_customer_id': null,
      'provider_subscription_id': null,
      'provider_payment_intent_id': null,
      'idempotency_key': idempotencyKey,
      'created_at': nowUtc,
      'updated_at': nowUtc,
    };
    _purchases[purchaseId] = purchase;
    _idempotencyLookup[replayKey] = purchaseId;
    final initialAssignments = assignments.isEmpty
        ? <Map<String, Object?>>[
            <String, Object?>{
              'seat_index': 1,
              'assignee_user_id': userId,
              'role': 'admin',
            },
          ]
        : assignments;
    await replaceAssignments(
      purchaseId: purchaseId,
      assignments: initialAssignments,
    );
    return <String, Object?>{...purchase, '_replayed': false};
  }

  @override
  Future<Map<String, Object?>?> findPurchaseById(String purchaseId) async {
    final purchase = _purchases[purchaseId];
    return purchase == null ? null : Map<String, Object?>.from(purchase);
  }

  @override
  Future<Map<String, Object?>?> findPurchaseByIdempotency({
    required String userId,
    required String idempotencyKey,
  }) async {
    final purchaseId = _idempotencyLookup['$userId|$idempotencyKey'];
    if (purchaseId == null) {
      return null;
    }
    final purchase = _purchases[purchaseId];
    return purchase == null ? null : Map<String, Object?>.from(purchase);
  }

  @override
  Future<Map<String, Object?>?> findPurchaseByProviderRef({
    required String provider,
    required String providerRef,
  }) async {
    for (final purchase in _purchases.values) {
      if (purchase['provider'] == provider &&
          purchase['provider_payment_intent_id'] == providerRef) {
        return Map<String, Object?>.from(purchase);
      }
    }
    return null;
  }

  @override
  Future<void> updatePurchaseStatus({
    required String purchaseId,
    required String status,
    String? providerCustomerId,
    String? providerSubscriptionId,
    String? providerPaymentIntentId,
  }) async {
    final purchase = _purchases[purchaseId];
    if (purchase == null) {
      return;
    }
    purchase['status'] = status;
    if (providerCustomerId != null) {
      purchase['provider_customer_id'] = providerCustomerId;
    }
    if (providerSubscriptionId != null) {
      purchase['provider_subscription_id'] = providerSubscriptionId;
    }
    if (providerPaymentIntentId != null) {
      purchase['provider_payment_intent_id'] = providerPaymentIntentId;
    }
    purchase['updated_at'] = DateTime.now().toUtc();
  }

  @override
  Future<Map<String, Object?>> updatePurchaseSeats({
    required String purchaseId,
    required int seatCount,
  }) async {
    final purchase = _purchases[purchaseId];
    if (purchase == null) {
      throw StateError('purchase_not_found');
    }
    purchase['seats_total'] = seatCount;
    purchase['updated_at'] = DateTime.now().toUtc();
    return Map<String, Object?>.from(purchase);
  }

  @override
  Future<Map<String, Object?>> updatePurchasePlan({
    required String purchaseId,
    required String offerId,
  }) async {
    final purchase = _purchases[purchaseId];
    if (purchase == null) {
      throw StateError('purchase_not_found');
    }
    final offer = _offers[offerId];
    if (offer == null) {
      throw StateError('offer_not_found');
    }
    purchase['offer_id'] = offerId;
    purchase['currency'] = offer['currency'];
    purchase['price_minor'] = offer['price_minor'];
    purchase['updated_at'] = DateTime.now().toUtc();
    return Map<String, Object?>.from(purchase);
  }

  @override
  Future<List<Map<String, Object?>>> listAssignments(String purchaseId) async {
    final assignments =
        _assignments[purchaseId] ?? const <Map<String, Object?>>[];
    return assignments
        .map((assignment) => Map<String, Object?>.from(assignment))
        .toList(growable: false);
  }

  @override
  Future<void> replaceAssignments({
    required String purchaseId,
    required List<Map<String, Object?>> assignments,
  }) async {
    final nowUtc = DateTime.now().toUtc();
    final seenAssignees = <String>{};
    final rows = <Map<String, Object?>>[];
    for (var index = 0; index < assignments.length; index++) {
      final assignment = assignments[index];
      final assignee =
          (assignment['assignee_user_id'] as String?)?.trim() ??
          (assignment['email'] as String?)?.trim() ??
          (assignment['name'] as String?)?.trim() ??
          '';
      if (assignee.isEmpty || seenAssignees.contains(assignee)) {
        continue;
      }
      seenAssignees.add(assignee);
      final seatIndex =
          (assignment['seat_index'] as num?)?.toInt() ?? (index + 1);
      rows.add(<String, Object?>{
        'id': _uuid.v4(),
        'purchase_id': purchaseId,
        'seat_index': seatIndex <= 0 ? (index + 1) : seatIndex,
        'assignee_user_id': assignee,
        'role':
            (assignment['role'] as String?)?.trim().toLowerCase() ?? 'member',
        'created_at': nowUtc,
        'updated_at': nowUtc,
      });
    }
    _assignments[purchaseId] = rows;
  }

  @override
  Future<void> appendTimelineEvent({
    required String purchaseId,
    required String eventType,
    required Map<String, Object?> eventData,
    DateTime? createdAtUtc,
  }) async {
    final timeline = _timeline.putIfAbsent(
      purchaseId,
      () => <Map<String, Object?>>[],
    );
    timeline.add(<String, Object?>{
      'id': _uuid.v4(),
      'purchase_id': purchaseId,
      'event_type': eventType,
      'event_data': Map<String, Object?>.from(eventData),
      'created_at': (createdAtUtc ?? DateTime.now().toUtc()),
    });
  }

  @override
  Future<List<Map<String, Object?>>> listTimelineEvents(
    String purchaseId, {
    int limit = 50,
  }) async {
    final timeline = _timeline[purchaseId] ?? const <Map<String, Object?>>[];
    return timeline
        .take(limit <= 0 ? 50 : limit)
        .map((event) => Map<String, Object?>.from(event))
        .toList(growable: false);
  }

  @override
  Future<bool> recordWebhookEvent({
    required String provider,
    required String providerEventId,
    required String eventType,
    required Map<String, Object?> payload,
    String? purchaseId,
  }) async {
    final key = '$provider|$providerEventId';
    if (_webhooks.containsKey(key)) {
      return false;
    }
    _webhooks[key] = <String, Object?>{
      'id': _uuid.v4(),
      'provider': provider,
      'provider_event_id': providerEventId,
      'purchase_id': purchaseId,
      'event_type': eventType,
      'payload_json': Map<String, Object?>.from(payload),
      'processed': false,
      'created_at': DateTime.now().toUtc(),
      'processed_at': null,
    };
    return true;
  }

  @override
  Future<void> markWebhookProcessed({
    required String provider,
    required String providerEventId,
  }) async {
    final key = '$provider|$providerEventId';
    final webhook = _webhooks[key];
    if (webhook == null) {
      return;
    }
    webhook['processed'] = true;
    webhook['processed_at'] = DateTime.now().toUtc();
  }

  @override
  Future<List<Map<String, Object?>>> listWebhookEvents(
    String purchaseId,
  ) async {
    return _webhooks.values
        .where((event) => event['purchase_id'] == purchaseId)
        .map((event) => Map<String, Object?>.from(event))
        .toList(growable: false);
  }
}
