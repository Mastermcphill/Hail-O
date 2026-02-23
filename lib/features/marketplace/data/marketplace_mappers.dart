import '../models/offer.dart';
import '../models/paywall_copy.dart';
import '../models/purchase_receipt.dart';
import '../models/timeline_event.dart';
import 'marketplace_repository.dart';

List<Offer> mapOffersFromEnvelope(Map<String, dynamic> response) {
  final payload = _envelopeData(response);
  final offerList = _extractList(payload, listKey: 'offers');
  return offerList.map(Offer.fromMap).toList(growable: false);
}

PaywallCopy mapPaywallFromEnvelope(Map<String, dynamic> response) {
  final payload = _envelopeData(response);
  final map = _extractMap(payload, mapKey: 'paywall');
  return PaywallCopy.fromMap(map);
}

String mapPurchaseIdFromEnvelope(Map<String, dynamic> response) {
  final payload = _asMap(_envelopeData(response));
  final purchaseId = _readString(payload['purchase_id']);
  if (purchaseId.isNotEmpty) {
    return purchaseId;
  }
  final purchase = _extractMap(payload, mapKey: 'purchase');
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

String? mapRestoredPurchaseIdFromEnvelope(Map<String, dynamic> response) {
  final payload = _asMap(_envelopeData(response));
  final purchaseId = _readString(payload['purchase_id']);
  if (purchaseId.isNotEmpty) {
    return purchaseId;
  }
  final purchase = _extractMap(payload, mapKey: 'purchase');
  final nestedId = _readString(purchase['id']).isNotEmpty
      ? _readString(purchase['id'])
      : _readString(purchase['purchase_id']);
  if (nestedId.isNotEmpty) {
    return nestedId;
  }
  return null;
}

PurchaseReceipt mapPurchaseReceiptFromEnvelope(Map<String, dynamic> response) {
  final payload = _asMap(_envelopeData(response));
  return PurchaseReceipt.fromMap(payload);
}

List<TimelineEvent> mapTimelineFromEnvelope(Map<String, dynamic> response) {
  final payload = _envelopeData(response);
  final eventList = _extractList(payload, listKey: 'events');
  return eventList.map(TimelineEvent.fromMap).toList(growable: false);
}

dynamic _envelopeData(Map<String, dynamic> source) {
  if (source.containsKey('data')) {
    return source['data'];
  }
  return source;
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
