import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/offer.dart';
import '../models/outbox_item.dart';
import '../models/purchase_snapshot.dart';
import '../models/timeline_event.dart';

class MarketplaceLocalStore {
  const MarketplaceLocalStore({this.databaseName = 'marketplace'});

  final String databaseName;

  Future<void> close() async {}

  Future<void> setMeta(String key, String value) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_metaKey(key), value);
  }

  Future<String?> getMeta(String key) async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(_metaKey(key));
  }

  Future<void> cacheOffers(
    List<MarketplaceOffer> offers, {
    String? etag,
  }) async {
    final prefs = await SharedPreferences.getInstance();
    final encoded = jsonEncode(
      offers.map((offer) => offer.toJson()).toList(growable: false),
    );
    await prefs.setString(_offersKey(), encoded);
    if (etag != null && etag.trim().isNotEmpty) {
      await prefs.setString(_metaKey('lastOffersEtag'), etag.trim());
    }
    await prefs.setString(
      _metaKey('offersLastSyncAt'),
      DateTime.now().toUtc().toIso8601String(),
    );
  }

  Future<List<MarketplaceOffer>> readOffers() async {
    final prefs = await SharedPreferences.getInstance();
    final encoded = prefs.getString(_offersKey());
    if (encoded == null || encoded.trim().isEmpty) {
      return const <MarketplaceOffer>[];
    }
    final decoded = jsonDecode(encoded);
    if (decoded is! List) {
      return const <MarketplaceOffer>[];
    }
    return decoded
        .whereType<Map>()
        .map(
          (item) => Offer.fromJson(
            item.map(
              (key, value) => MapEntry<String, dynamic>(key.toString(), value),
            ),
          ),
        )
        .toList(growable: false);
  }

  Future<void> cachePurchase(
    MarketplacePurchaseSnapshot snapshot, {
    String? etag,
  }) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(
      _purchaseKey(snapshot.purchaseId),
      jsonEncode(snapshot.toJson()),
    );
    await prefs.setString(
      _metaKey('lastPurchaseVersion:${snapshot.purchaseId}'),
      '${snapshot.version}',
    );
    if (etag != null && etag.trim().isNotEmpty) {
      await prefs.setString(
        _metaKey('purchaseEtag:${snapshot.purchaseId}'),
        etag.trim(),
      );
    }
    await prefs.setString(
      _metaKey('purchaseLastSyncAt:${snapshot.purchaseId}'),
      DateTime.now().toUtc().toIso8601String(),
    );
  }

  Future<MarketplacePurchaseSnapshot?> readPurchase(String purchaseId) async {
    final prefs = await SharedPreferences.getInstance();
    final encoded = prefs.getString(_purchaseKey(purchaseId));
    if (encoded == null || encoded.trim().isEmpty) {
      return null;
    }
    final decoded = jsonDecode(encoded);
    if (decoded is! Map) {
      return null;
    }
    return MarketplacePurchaseSnapshot.fromJson(
      decoded.map(
        (key, value) => MapEntry<String, dynamic>(key.toString(), value),
      ),
    );
  }

  Future<void> mergeTimeline(
    String purchaseId,
    List<MarketplaceTimelineEvent> events, {
    String? latestEventAt,
    String? cursor,
  }) async {
    final existing = await readTimeline(purchaseId);
    final keyed = <String, MarketplaceTimelineEvent>{
      for (final event in existing) _timelineEventKey(event): event,
    };
    for (final event in events) {
      keyed[_timelineEventKey(event)] = event;
    }
    final merged = keyed.values.toList(growable: false)
      ..sort((left, right) {
        final lt = left.timestamp?.millisecondsSinceEpoch ?? 0;
        final rt = right.timestamp?.millisecondsSinceEpoch ?? 0;
        if (lt != rt) {
          return lt.compareTo(rt);
        }
        return _timelineEventKey(left).compareTo(_timelineEventKey(right));
      });

    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(
      _timelineKey(purchaseId),
      jsonEncode(merged.map((event) => event.toJson()).toList(growable: false)),
    );
    if (latestEventAt != null && latestEventAt.trim().isNotEmpty) {
      await prefs.setString(
        _metaKey('lastTimelineAt:$purchaseId'),
        latestEventAt.trim(),
      );
    }
    if (cursor != null && cursor.trim().isNotEmpty) {
      await prefs.setString(
        _metaKey('lastTimelineCursor:$purchaseId'),
        cursor.trim(),
      );
    }
  }

  Future<List<MarketplaceTimelineEvent>> readTimeline(String purchaseId) async {
    final prefs = await SharedPreferences.getInstance();
    final encoded = prefs.getString(_timelineKey(purchaseId));
    if (encoded == null || encoded.trim().isEmpty) {
      return const <MarketplaceTimelineEvent>[];
    }
    final decoded = jsonDecode(encoded);
    if (decoded is! List) {
      return const <MarketplaceTimelineEvent>[];
    }
    final rows = decoded
        .whereType<Map>()
        .map(
          (item) => TimelineEvent.fromJson(
            item.map(
              (key, value) => MapEntry<String, dynamic>(key.toString(), value),
            ),
          ),
        )
        .toList(growable: false);
    rows.sort((left, right) {
      final lt = left.timestamp?.millisecondsSinceEpoch ?? 0;
      final rt = right.timestamp?.millisecondsSinceEpoch ?? 0;
      if (lt != rt) {
        return lt.compareTo(rt);
      }
      return _timelineEventKey(left).compareTo(_timelineEventKey(right));
    });
    return rows;
  }

  Future<void> upsertOutboxItem(MarketplaceOutboxItem item) async {
    final items = await readAllOutboxItems();
    final index = items.indexWhere((entry) => entry.id == item.id);
    final next = List<MarketplaceOutboxItem>.from(items);
    if (index >= 0) {
      next[index] = item;
    } else {
      next.add(item);
    }
    await _writeAllOutboxItems(next);
  }

  Future<List<MarketplaceOutboxItem>> readDueOutboxItems({
    DateTime? nowUtc,
  }) async {
    final now = (nowUtc ?? DateTime.now().toUtc()).toUtc();
    final items = await readAllOutboxItems();
    final due = items
        .where((item) {
          final queued =
              item.status == MarketplaceOutboxStatus.queued ||
              item.status == MarketplaceOutboxStatus.failed;
          if (!queued) {
            return false;
          }
          final nextRetryAt = item.nextRetryAt;
          if (nextRetryAt == null) {
            return true;
          }
          return !nextRetryAt.isAfter(now);
        })
        .toList(growable: false);
    due.sort((left, right) => left.createdAt.compareTo(right.createdAt));
    return due;
  }

  Future<void> updateOutboxStatus({
    required String id,
    required MarketplaceOutboxStatus status,
    required int attempts,
    DateTime? nextRetryAt,
    String? lastError,
    int? baseVersion,
  }) async {
    final items = await readAllOutboxItems();
    final index = items.indexWhere((item) => item.id == id);
    if (index < 0) {
      return;
    }
    final existing = items[index];
    final updated = existing.copyWith(
      status: status,
      attempts: attempts,
      nextRetryAt: nextRetryAt,
      clearNextRetryAt: nextRetryAt == null,
      lastError: lastError,
      baseVersion: baseVersion ?? existing.baseVersion,
    );
    final next = List<MarketplaceOutboxItem>.from(items)..[index] = updated;
    await _writeAllOutboxItems(next);
  }

  Future<void> deleteOutboxItem(String id) async {
    final items = await readAllOutboxItems();
    final next = items.where((item) => item.id != id).toList(growable: false);
    await _writeAllOutboxItems(next);
  }

  Future<List<MarketplaceOutboxItem>> readAllOutboxItems() async {
    final prefs = await SharedPreferences.getInstance();
    final encoded = prefs.getString(_outboxKey());
    if (encoded == null || encoded.trim().isEmpty) {
      return const <MarketplaceOutboxItem>[];
    }
    final decoded = jsonDecode(encoded);
    if (decoded is! List) {
      return const <MarketplaceOutboxItem>[];
    }
    final items = decoded
        .whereType<Map>()
        .map(
          (item) => MarketplaceOutboxItem.fromJson(
            item.map(
              (key, value) => MapEntry<String, dynamic>(key.toString(), value),
            ),
          ),
        )
        .toList(growable: false);
    items.sort((left, right) => left.createdAt.compareTo(right.createdAt));
    return items;
  }

  Future<void> _writeAllOutboxItems(List<MarketplaceOutboxItem> items) async {
    final prefs = await SharedPreferences.getInstance();
    final encoded = jsonEncode(
      items.map((item) => item.toJson()).toList(growable: false),
    );
    await prefs.setString(_outboxKey(), encoded);
  }

  Future<String?> readCheckoutIdempotencyKey(String signature) async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(_signatureToIdempotencyKey(signature));
  }

  Future<void> writeCheckoutIdempotencyKey({
    required String signature,
    required String idempotencyKey,
  }) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(
      _signatureToIdempotencyKey(signature),
      idempotencyKey,
    );
  }

  Future<String?> readPendingCheckoutKeyForOffer(String offerId) async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(_pendingCheckoutKeyForOffer(offerId));
  }

  Future<void> writePendingCheckoutKeyForOffer({
    required String offerId,
    required String idempotencyKey,
  }) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_pendingCheckoutKeyForOffer(offerId), idempotencyKey);
  }

  Future<void> clearPendingCheckoutKeyForOffer(String offerId) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_pendingCheckoutKeyForOffer(offerId));
  }

  Future<String?> readPurchaseIdByIdempotencyKey(String idempotencyKey) async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(_idempotencyKeyToPurchase(idempotencyKey));
  }

  Future<void> writePurchaseIdByIdempotencyKey({
    required String idempotencyKey,
    required String purchaseId,
  }) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(
      _idempotencyKeyToPurchase(idempotencyKey),
      purchaseId,
    );
  }

  Future<String?> readCouponCode(String orgId) async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(_couponCodeKey(orgId));
  }

  Future<void> writeCouponCode({
    required String orgId,
    required String couponCode,
  }) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_couponCodeKey(orgId), couponCode);
  }

  Future<void> clearCouponCode(String orgId) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_couponCodeKey(orgId));
  }

  Future<String?> readReferralCode(String orgId) async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(_referralCodeKey(orgId));
  }

  Future<void> writeReferralCode({
    required String orgId,
    required String referralCode,
  }) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_referralCodeKey(orgId), referralCode);
  }

  Future<void> clearReferralCode(String orgId) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_referralCodeKey(orgId));
  }

  String _metaKey(String key) {
    return _namespaced('meta.${_digest(key)}');
  }

  String _offersKey() {
    return _namespaced('offers');
  }

  String _purchaseKey(String purchaseId) {
    return _namespaced('purchase.${_digest(purchaseId)}');
  }

  String _timelineKey(String purchaseId) {
    return _namespaced('timeline.${_digest(purchaseId)}');
  }

  String _outboxKey() {
    return _namespaced('outbox');
  }

  String _signatureToIdempotencyKey(String signature) {
    return _namespaced('checkout.signature.${_digest(signature)}');
  }

  String _pendingCheckoutKeyForOffer(String offerId) {
    return _namespaced('checkout.pending.${_digest(offerId)}');
  }

  String _idempotencyKeyToPurchase(String idempotencyKey) {
    return _namespaced('checkout.purchase.${_digest(idempotencyKey)}');
  }

  String _couponCodeKey(String orgId) {
    return _namespaced('pricing.coupon.${_digest(orgId)}');
  }

  String _referralCodeKey(String orgId) {
    return _namespaced('pricing.referral.${_digest(orgId)}');
  }

  String _namespaced(String suffix) {
    return 'marketplace.$databaseName.$suffix';
  }

  String _digest(String value) {
    return sha1.convert(utf8.encode(value)).toString();
  }

  String _timelineEventKey(MarketplaceTimelineEvent event) {
    final cursor = event.cursor ?? '';
    final timestamp = event.timestamp?.toIso8601String() ?? '';
    return '$cursor|${event.type}|$timestamp|${event.description}';
  }
}
