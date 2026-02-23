import 'dart:collection';

import 'package:hailo_core/features/marketplace/data/marketplace_local_store.dart';
import 'package:hailo_core/features/marketplace/models/offer.dart';
import 'package:hailo_core/features/marketplace/models/outbox_item.dart';
import 'package:hailo_core/features/marketplace/models/purchase_snapshot.dart';
import 'package:hailo_core/features/marketplace/models/timeline_event.dart';

class MemoryMarketplaceLocalStore extends MarketplaceLocalStore {
  MemoryMarketplaceLocalStore({required this.namespace})
    : super(databaseName: ':memory:$namespace');

  final String namespace;

  static final Map<String, _MemoryState> _stateByNamespace =
      <String, _MemoryState>{};

  _MemoryState get _state =>
      _stateByNamespace.putIfAbsent(namespace, _MemoryState.new);

  @override
  Future<void> close() async {}

  @override
  Future<void> setMeta(String key, String value) async {
    _state.meta[key] = value;
  }

  @override
  Future<String?> getMeta(String key) async {
    return _state.meta[key];
  }

  @override
  Future<void> cacheOffers(
    List<MarketplaceOffer> offers, {
    String? etag,
  }) async {
    _state.offers
      ..clear()
      ..addAll(offers);
    if (etag != null && etag.trim().isNotEmpty) {
      _state.meta['lastOffersEtag'] = etag.trim();
    }
    _state.meta['offersLastSyncAt'] = DateTime.now().toUtc().toIso8601String();
  }

  @override
  Future<List<MarketplaceOffer>> readOffers() async {
    return List<MarketplaceOffer>.from(_state.offers);
  }

  @override
  Future<void> cachePurchase(
    MarketplacePurchaseSnapshot snapshot, {
    String? etag,
  }) async {
    _state.purchases[snapshot.purchaseId] = snapshot;
    _state.meta['lastPurchaseVersion:${snapshot.purchaseId}'] =
        '${snapshot.version}';
    if (etag != null && etag.trim().isNotEmpty) {
      _state.meta['purchaseEtag:${snapshot.purchaseId}'] = etag.trim();
    }
    _state.meta['purchaseLastSyncAt:${snapshot.purchaseId}'] = DateTime.now()
        .toUtc()
        .toIso8601String();
  }

  @override
  Future<MarketplacePurchaseSnapshot?> readPurchase(String purchaseId) async {
    return _state.purchases[purchaseId];
  }

  @override
  Future<void> mergeTimeline(
    String purchaseId,
    List<MarketplaceTimelineEvent> events, {
    String? latestEventAt,
    String? cursor,
  }) async {
    final timelineByKey = _state.timelineByPurchase.putIfAbsent(
      purchaseId,
      LinkedHashMap<String, MarketplaceTimelineEvent>.new,
    );
    for (final event in events) {
      timelineByKey[_timelineEventKey(event)] = event;
    }
    if (latestEventAt != null && latestEventAt.trim().isNotEmpty) {
      _state.meta['lastTimelineAt:$purchaseId'] = latestEventAt;
    }
    if (cursor != null && cursor.trim().isNotEmpty) {
      _state.meta['lastTimelineCursor:$purchaseId'] = cursor;
    }
  }

  @override
  Future<List<MarketplaceTimelineEvent>> readTimeline(String purchaseId) async {
    final values =
        _state.timelineByPurchase[purchaseId]?.values.toList(growable: false) ??
        const <MarketplaceTimelineEvent>[];
    final copy = List<MarketplaceTimelineEvent>.from(values);
    copy.sort((left, right) {
      final lt = left.timestamp?.millisecondsSinceEpoch ?? 0;
      final rt = right.timestamp?.millisecondsSinceEpoch ?? 0;
      if (lt != rt) {
        return lt.compareTo(rt);
      }
      return _timelineEventKey(left).compareTo(_timelineEventKey(right));
    });
    return copy;
  }

  @override
  Future<void> upsertOutboxItem(MarketplaceOutboxItem item) async {
    _state.outbox[item.id] = item;
  }

  @override
  Future<List<MarketplaceOutboxItem>> readDueOutboxItems({
    DateTime? nowUtc,
  }) async {
    final now = nowUtc ?? DateTime.now().toUtc();
    final due = _state.outbox.values
        .where((item) {
          final isQueued =
              item.status == MarketplaceOutboxStatus.queued ||
              item.status == MarketplaceOutboxStatus.failed;
          if (!isQueued) {
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

  @override
  Future<void> updateOutboxStatus({
    required String id,
    required MarketplaceOutboxStatus status,
    required int attempts,
    DateTime? nextRetryAt,
    String? lastError,
    int? baseVersion,
  }) async {
    final existing = _state.outbox[id];
    if (existing == null) {
      return;
    }
    _state.outbox[id] = MarketplaceOutboxItem(
      id: existing.id,
      type: existing.type,
      purchaseId: existing.purchaseId,
      idempotencyKey: existing.idempotencyKey,
      payload: existing.payload,
      baseVersion: baseVersion ?? existing.baseVersion,
      status: status,
      attempts: attempts,
      nextRetryAt: nextRetryAt,
      createdAt: existing.createdAt,
      lastError: lastError,
    );
  }

  @override
  Future<void> deleteOutboxItem(String id) async {
    _state.outbox.remove(id);
  }

  @override
  Future<List<MarketplaceOutboxItem>> readAllOutboxItems() async {
    final all = _state.outbox.values.toList(growable: false);
    all.sort((left, right) => left.createdAt.compareTo(right.createdAt));
    return all;
  }

  String _timelineEventKey(MarketplaceTimelineEvent event) {
    final cursor = event.cursor ?? '';
    final timestamp = event.timestamp?.toIso8601String() ?? '';
    return '$cursor|${event.type}|$timestamp|${event.description}';
  }
}

class _MemoryState {
  final Map<String, String> meta = <String, String>{};
  final List<MarketplaceOffer> offers = <MarketplaceOffer>[];
  final Map<String, MarketplacePurchaseSnapshot> purchases =
      <String, MarketplacePurchaseSnapshot>{};
  final Map<String, LinkedHashMap<String, MarketplaceTimelineEvent>>
  timelineByPurchase =
      <String, LinkedHashMap<String, MarketplaceTimelineEvent>>{};
  final Map<String, MarketplaceOutboxItem> outbox =
      <String, MarketplaceOutboxItem>{};
}
