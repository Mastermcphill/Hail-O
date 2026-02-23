import '../models/offer.dart';
import '../models/paywall_copy.dart';
import '../models/pricing_breakdown.dart';
import '../models/purchase_receipt.dart';
import '../models/timeline_event.dart';
import '../models/billing_invoice.dart';
import 'marketplace_repository.dart';

dynamic extractEnvelopeData(Map<String, dynamic> envelope) {
  if (envelope.containsKey('data')) {
    return envelope['data'];
  }
  return envelope;
}

List<Offer> mapOffersPayload(dynamic payload) {
  final offerList = _extractList(payload, listKey: 'offers');
  final normalized = offerList.map(_normalizeOfferMap).toList(growable: false);
  return normalized.map(Offer.fromMap).toList(growable: false);
}

List<Offer> mapOffersFromEnvelope(Map<String, dynamic> response) {
  return mapOffersPayload(extractEnvelopeData(response));
}

PaywallCopy mapPaywallPayload(dynamic payload) {
  final map = _extractMap(payload, mapKey: 'paywall');
  return PaywallCopy.fromMap(_normalizePaywallMap(map));
}

PaywallCopy mapPaywallFromEnvelope(Map<String, dynamic> response) {
  return mapPaywallPayload(extractEnvelopeData(response));
}

String mapPurchaseIdPayload(dynamic payload) {
  final map = _normalizePurchaseMap(_asMap(payload));
  final purchaseId = _readString(map['purchase_id']);
  if (purchaseId.isNotEmpty) {
    return purchaseId;
  }
  final purchase = _normalizePurchaseMap(_extractMap(map, mapKey: 'purchase'));
  final nestedId = _readString(purchase['id']).isNotEmpty
      ? _readString(purchase['id'])
      : _readString(purchase['purchase_id']);
  if (nestedId.isNotEmpty) {
    return nestedId;
  }
  throw const MarketplaceRepositoryException(
    'Checkout completed but purchase id was missing.',
    code: 'missing_purchase_id',
  );
}

String mapPurchaseIdFromEnvelope(Map<String, dynamic> response) {
  return mapPurchaseIdPayload(extractEnvelopeData(response));
}

String? mapRestoredPurchaseIdPayload(dynamic payload) {
  final map = _normalizePurchaseMap(_asMap(payload));
  final purchaseId = _readString(map['purchase_id']);
  if (purchaseId.isNotEmpty) {
    return purchaseId;
  }
  final purchase = _normalizePurchaseMap(_extractMap(map, mapKey: 'purchase'));
  final nestedId = _readString(purchase['id']).isNotEmpty
      ? _readString(purchase['id'])
      : _readString(purchase['purchase_id']);
  if (nestedId.isNotEmpty) {
    return nestedId;
  }
  return null;
}

String? mapRestoredPurchaseIdFromEnvelope(Map<String, dynamic> response) {
  return mapRestoredPurchaseIdPayload(extractEnvelopeData(response));
}

PurchaseReceipt mapPurchaseReceiptPayload(dynamic payload) {
  final map = _normalizePurchaseMap(_asMap(payload));
  return PurchaseReceipt.fromMap(map);
}

PurchaseReceipt mapPurchaseReceiptFromEnvelope(Map<String, dynamic> response) {
  return mapPurchaseReceiptPayload(extractEnvelopeData(response));
}

List<TimelineEvent> mapTimelinePayload(dynamic payload) {
  final eventList = _extractList(payload, listKey: 'events');
  final normalized = eventList
      .map(_normalizeTimelineEventMap)
      .toList(growable: false);
  return normalized.map(TimelineEvent.fromMap).toList(growable: false);
}

List<TimelineEvent> mapTimelineFromEnvelope(Map<String, dynamic> response) {
  return mapTimelinePayload(extractEnvelopeData(response));
}

PricingBreakdown mapPricingBreakdownPayload(dynamic payload) {
  final map = _asMap(payload);
  return PricingBreakdown.fromMap(map);
}

PricingBreakdown mapPricingBreakdownFromEnvelope(Map<String, dynamic> response) {
  return mapPricingBreakdownPayload(extractEnvelopeData(response));
}

List<BillingInvoice> mapInvoiceListPayload(dynamic payload) {
  final list = _extractList(payload, listKey: 'invoices');
  return list
      .map((item) => BillingInvoice.fromMap(item))
      .toList(growable: false);
}

List<BillingInvoice> mapInvoiceListFromEnvelope(Map<String, dynamic> response) {
  return mapInvoiceListPayload(extractEnvelopeData(response));
}

BillingInvoice? mapSingleInvoicePayload(dynamic payload) {
  final map = _asMap(payload);
  if (map.isEmpty) {
    return null;
  }
  return BillingInvoice.fromMap(map);
}

Map<String, dynamic> _normalizeOfferMap(Map<String, dynamic> map) {
  return <String, dynamic>{
    'id': _firstNonEmptyString(<Object?>[map['id']]),
    'title': _firstNonEmptyString(<Object?>[map['title']]),
    'vehicle_class': _firstNonEmptyString(<Object?>[
      map['vehicle_class'],
      map['vehicleClass'],
      map['subtitle'],
      'marketplace',
    ]),
    'price_minor': _firstInt(<Object?>[map['price_minor'], map['price']]),
    'rating': _firstNum(<Object?>[map['rating']], fallback: 0),
    'seats_available': _firstInt(<Object?>[
      map['seats_available'],
      map['seatsAvailable'],
    ], fallback: 1),
    'eta_minutes': _firstInt(<Object?>[
      map['eta_minutes'],
      map['etaMinutes'],
    ], fallback: 0),
    'highlights': _firstStringList(<Object?>[map['highlights'], map['perks']]),
  };
}

Map<String, dynamic> _normalizePaywallMap(Map<String, dynamic> map) {
  return <String, dynamic>{
    'offer_id': _firstNonEmptyString(<Object?>[
      map['offer_id'],
      map['offerId'],
    ]),
    'headline': _firstNonEmptyString(<Object?>[map['headline']]),
    'bullets': _firstStringList(<Object?>[map['bullets']]),
    'legal_text': _firstNonEmptyString(<Object?>[
      map['legal_text'],
      map['legalText'],
    ]),
    'cta_label': _firstNonEmptyString(<Object?>[
      map['cta_label'],
      map['ctaLabel'],
      'Continue',
    ]),
    'connection_fee_minor': _firstInt(<Object?>[
      map['connection_fee_minor'],
      map['connectionFeeMinor'],
    ], fallback: 0),
  };
}

Map<String, dynamic> _normalizePurchaseMap(Map<String, dynamic> map) {
  final normalizedAssignments = _normalizeAssignments(map['assignments']);
  return <String, dynamic>{
    'purchase_id': _firstNonEmptyString(<Object?>[
      map['purchase_id'],
      map['purchaseId'],
      map['id'],
    ]),
    'id': _firstNonEmptyString(<Object?>[
      map['id'],
      map['purchase_id'],
      map['purchaseId'],
    ]),
    'offer_id': _firstNonEmptyString(<Object?>[
      map['offer_id'],
      map['offerId'],
    ]),
    'offer_title': _firstNonEmptyString(<Object?>[
      map['offer_title'],
      map['offerTitle'],
      map['subtitle'],
    ]),
    'seat_count': _firstInt(<Object?>[
      map['seat_count'],
      map['seatCount'],
    ], fallback: 0),
    'total_price_minor': _firstInt(<Object?>[
      map['total_price_minor'],
      map['totalPriceMinor'],
      map['totalAmount'],
    ], fallback: 0),
    'status': _firstNonEmptyString(<Object?>[map['status'], 'PENDING']),
    'created_at': _firstNonEmptyString(<Object?>[
      map['created_at'],
      map['createdAt'],
    ]),
    'assignments': normalizedAssignments,
  };
}

List<Map<String, dynamic>> _normalizeAssignments(Object? value) {
  if (value is! List) {
    return const <Map<String, dynamic>>[];
  }
  return value
      .whereType<Map>()
      .map((entry) {
        final map = _asMap(entry);
        return <String, dynamic>{
          'seat_number': _firstInt(<Object?>[
            map['seat_number'],
            map['seatIndex'],
          ], fallback: 0),
          'name': _firstNonEmptyString(<Object?>[map['name']]),
          'email': _firstNonEmptyString(<Object?>[map['email']]),
        };
      })
      .toList(growable: false);
}

Map<String, dynamic> _normalizeTimelineEventMap(Map<String, dynamic> map) {
  final type = _firstNonEmptyString(<Object?>[map['type']]);
  final title = _firstNonEmptyString(<Object?>[type, map['title']]);
  final timestamp = _firstNonEmptyString(<Object?>[
    map['occurred_at'],
    map['timestamp'],
  ]);
  return <String, dynamic>{
    'id': _firstNonEmptyString(<Object?>[map['id'], type, timestamp]),
    'title': title,
    'description': _firstNonEmptyString(<Object?>[map['description']]),
    'occurred_at': timestamp,
    'status': _firstNonEmptyString(<Object?>[map['status'], 'pending']),
  };
}

List<Map<String, dynamic>> _extractList(
  dynamic source, {
  required String listKey,
}) {
  if (source is List) {
    return _toMapList(source);
  }

  final map = _asMap(source);
  final direct = map[listKey];
  if (direct is List) {
    return _toMapList(direct);
  }

  final data = map['data'];
  if (data is List) {
    return _toMapList(data);
  }
  if (data is Map && data[listKey] is List) {
    return _toMapList(data[listKey] as List<dynamic>);
  }
  return <Map<String, dynamic>>[];
}

Map<String, dynamic> _extractMap(dynamic source, {required String mapKey}) {
  final map = _asMap(source);
  final directMap = map[mapKey];
  if (directMap is Map) {
    return _asMap(directMap);
  }

  final data = map['data'];
  if (data is Map) {
    if (data[mapKey] is Map) {
      return _asMap(data[mapKey]);
    }
    return _asMap(data);
  }
  return map;
}

List<Map<String, dynamic>> _toMapList(List<dynamic> values) {
  return values
      .whereType<Map>()
      .map(
        (item) => item.map(
          (key, value) => MapEntry<String, dynamic>(key.toString(), value),
        ),
      )
      .toList(growable: false);
}

Map<String, dynamic> _asMap(dynamic value) {
  if (value is Map<String, dynamic>) {
    return value;
  }
  if (value is Map) {
    return value.map(
      (key, mapValue) => MapEntry<String, dynamic>(key.toString(), mapValue),
    );
  }
  return <String, dynamic>{};
}

String _readString(Object? value) {
  if (value is String) {
    return value.trim();
  }
  return '';
}

String _firstNonEmptyString(List<Object?> candidates, {String fallback = ''}) {
  for (final candidate in candidates) {
    final value = _readString(candidate);
    if (value.isNotEmpty) {
      return value;
    }
  }
  return fallback;
}

int _firstInt(List<Object?> candidates, {int fallback = 0}) {
  for (final candidate in candidates) {
    if (candidate is int) {
      return candidate;
    }
    if (candidate is num) {
      return candidate.toInt();
    }
    if (candidate is String) {
      final parsed = int.tryParse(candidate.trim());
      if (parsed != null) {
        return parsed;
      }
    }
  }
  return fallback;
}

double _firstNum(List<Object?> candidates, {double fallback = 0}) {
  for (final candidate in candidates) {
    if (candidate is double) {
      return candidate;
    }
    if (candidate is num) {
      return candidate.toDouble();
    }
    if (candidate is String) {
      final parsed = double.tryParse(candidate.trim());
      if (parsed != null) {
        return parsed;
      }
    }
  }
  return fallback;
}

List<String> _firstStringList(List<Object?> candidates) {
  for (final candidate in candidates) {
    if (candidate is List) {
      return candidate.map((item) => item.toString()).toList(growable: false);
    }
  }
  return const <String>[];
}
