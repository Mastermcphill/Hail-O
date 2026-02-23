import '../../../core/api/api_client.dart';
import '../../../core/api/api_errors.dart';
import '../models/offer.dart';
import '../models/paywall_copy.dart';
import '../models/seat_selection.dart';
import '../models/timeline_event.dart';
import 'marketplace_repository.dart';

class MarketplaceRepositoryHttp implements MarketplaceRepository {
  MarketplaceRepositoryHttp({required ApiClient apiClient})
    : _apiClient = apiClient;

  final ApiClient _apiClient;

  @override
  Future<List<Offer>> fetchOffers() async {
    try {
      final response = await _apiClient.get('/marketplace/offers');
      final items = _extractList(response, listKey: 'offers');
      return items.map(Offer.fromMap).toList(growable: false);
    } catch (error) {
      throw _mapError(
        error,
        fallbackMessage: 'Unable to load marketplace offers right now.',
      );
    }
  }

  @override
  Future<PaywallCopy> fetchPaywallCopy(String offerId) async {
    try {
      final response = await _apiClient.get('/marketplace/paywall/$offerId');
      final map = _extractMap(response, mapKey: 'paywall');
      return PaywallCopy.fromMap(map);
    } catch (error) {
      throw _mapError(
        error,
        fallbackMessage: 'Unable to load paywall information for this offer.',
      );
    }
  }

  @override
  Future<String> createCheckout(
    SeatSelection selection, {
    required String idempotencyKey,
  }) async {
    try {
      final response = await _apiClient.post(
        '/marketplace/checkout',
        body: selection.toMap(),
        idempotencyKey: idempotencyKey,
      );
      final purchaseId = _readString(response['purchase_id']);
      if (purchaseId.isNotEmpty) {
        return purchaseId;
      }
      final purchaseMap = _asMap(response['purchase']);
      final nestedId = _readString(purchaseMap['id']).isNotEmpty
          ? _readString(purchaseMap['id'])
          : _readString(purchaseMap['purchase_id']);
      if (nestedId.isNotEmpty) {
        return nestedId;
      }
      throw const MarketplaceRepositoryException(
        'Checkout completed but purchase id was missing.',
        code: 'missing_purchase_id',
      );
    } on ApiException catch (error) {
      if (error.statusCode == 409) {
        final restored = await restorePurchaseByIdempotencyKey(idempotencyKey);
        if (restored != null && restored.isNotEmpty) {
          return restored;
        }
      }
      throw _mapError(
        error,
        fallbackMessage: 'Unable to create checkout at this time.',
      );
    } catch (error) {
      throw _mapError(
        error,
        fallbackMessage: 'Unable to create checkout at this time.',
      );
    }
  }

  @override
  Future<String?> restorePurchaseByIdempotencyKey(String idempotencyKey) async {
    final queryKey = Uri.encodeQueryComponent(idempotencyKey);
    try {
      final response = await _apiClient.get(
        '/marketplace/purchases/restore?idempotencyKey=$queryKey',
      );
      final direct = _readString(response['purchase_id']);
      if (direct.isNotEmpty) {
        return direct;
      }
      final purchaseMap = _asMap(response['purchase']);
      final nested = _readString(purchaseMap['id']).isNotEmpty
          ? _readString(purchaseMap['id'])
          : _readString(purchaseMap['purchase_id']);
      if (nested.isNotEmpty) {
        return nested;
      }
      return null;
    } on ApiException catch (error) {
      final code = (error.code ?? '').toLowerCase();
      if (error.statusCode == 404 || code == 'not_implemented') {
        return null;
      }
      throw _mapError(
        error,
        fallbackMessage: 'Unable to restore purchase at this time.',
      );
    } catch (error) {
      throw _mapError(
        error,
        fallbackMessage: 'Unable to restore purchase at this time.',
      );
    }
  }

  @override
  Future<List<TimelineEvent>> fetchTimeline(String purchaseId) async {
    try {
      final response = await _apiClient.get(
        '/marketplace/timeline/$purchaseId',
      );
      final items = _extractList(response, listKey: 'events');
      return items.map(TimelineEvent.fromMap).toList(growable: false);
    } catch (error) {
      throw _mapError(
        error,
        fallbackMessage: 'Unable to fetch timeline at this time.',
      );
    }
  }
}

MarketplaceRepositoryException _mapError(
  Object error, {
  required String fallbackMessage,
}) {
  if (error is MarketplaceRepositoryException) {
    return error;
  }
  if (error is ApiException) {
    if (error.statusCode == 404) {
      return MarketplaceRepositoryException(
        'Marketplace endpoint is not available on this backend yet.',
        code: error.code ?? 'endpoint_not_available',
      );
    }
    return MarketplaceRepositoryException(
      error.message,
      code: error.code ?? 'http_${error.statusCode}',
    );
  }
  return MarketplaceRepositoryException(
    fallbackMessage,
    code: 'unknown_marketplace_error',
  );
}

List<Map<String, dynamic>> _extractList(
  Map<String, dynamic> source, {
  required String listKey,
}) {
  final direct = source[listKey];
  if (direct is List) {
    return _toMapList(direct);
  }
  final data = source['data'];
  if (data is List) {
    return _toMapList(data);
  }
  if (data is Map && data[listKey] is List) {
    return _toMapList(data[listKey] as List<dynamic>);
  }
  return <Map<String, dynamic>>[];
}

Map<String, dynamic> _extractMap(
  Map<String, dynamic> source, {
  required String mapKey,
}) {
  final directMap = source[mapKey];
  if (directMap is Map) {
    return _asMap(directMap);
  }
  final data = source['data'];
  if (data is Map) {
    if (data[mapKey] is Map) {
      return _asMap(data[mapKey]);
    }
    return _asMap(data);
  }
  return _asMap(source);
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
