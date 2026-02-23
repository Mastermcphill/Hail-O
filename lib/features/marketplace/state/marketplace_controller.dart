import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../../core/api/api_errors.dart';
import '../../../core/util/ids.dart';
import '../data/marketplace_local_store.dart';
import '../data/marketplace_repository.dart';
import '../models/offer.dart';
import '../models/org_summary.dart';
import '../models/outbox_item.dart';
import '../models/paywall_copy.dart';
import '../models/purchase_snapshot.dart';
import '../models/timeline_event.dart';

class MarketplaceController extends ChangeNotifier {
  static const String activeOrgPrefsKey = 'marketplace.active_org_id';

  MarketplaceController({
    required MarketplaceRepository repository,
    required MarketplaceLocalStore localStore,
    Duration syncInterval = const Duration(seconds: 45),
  }) : _repository = repository,
       _localStore = localStore,
       _syncInterval = syncInterval;

  final MarketplaceRepository _repository;
  final MarketplaceLocalStore _localStore;
  final Duration _syncInterval;

  List<MarketplaceOffer> offers = <MarketplaceOffer>[];
  MarketplacePaywallCopy? paywallCopy;
  MarketplacePurchaseSnapshot? purchase;
  List<MarketplaceTimelineEvent> timeline = <MarketplaceTimelineEvent>[];
  List<MarketplaceOrgSummary> orgs = <MarketplaceOrgSummary>[];
  List<MarketplacePurchaseSnapshot> activeOrgPurchases =
      <MarketplacePurchaseSnapshot>[];

  bool isLoadingOffers = false;
  bool isLoadingPaywall = false;
  bool isSubmittingSeats = false;
  bool isSyncing = false;
  bool isLoadingOrgs = false;
  bool isLoadingBilling = false;
  bool offlineMode = false;
  String? infoBanner;

  String? activeOrgId;

  int pendingOutboxCount = 0;
  String? _activePurchaseId;
  Timer? _syncTimer;

  String? get activeOrgName {
    for (final org in orgs) {
      if (org.id == activeOrgId) {
        return org.name;
      }
    }
    return null;
  }

  String get activeOrgRole {
    for (final org in orgs) {
      if (org.id == activeOrgId) {
        return org.role;
      }
    }
    return 'viewer';
  }

  bool get canManageBilling {
    final role = activeOrgRole.toLowerCase();
    return role == 'owner' || role == 'admin' || role == 'billing';
  }

  bool get canManageOrgMembers {
    final role = activeOrgRole.toLowerCase();
    return role == 'owner' || role == 'admin';
  }

  bool get hasActiveOrg =>
      activeOrgId != null && activeOrgId!.trim().isNotEmpty;

  Future<void> initializeOffers() async {
    await loadOrgs();
    offers = await _localStore.readOffers();
    await _refreshPendingCount();
    notifyListeners();
    await refreshOffers();
    if (hasActiveOrg && canManageBilling) {
      await refreshActiveOrgPurchases();
    }
  }

  Future<void> refreshOffers() async {
    isLoadingOffers = true;
    notifyListeners();
    try {
      final etag = await _localStore.getMeta('lastOffersEtag');
      final response = await _repository.fetchOffers(ifNoneMatch: etag);
      if (!response.notModified && response.data != null) {
        offers = response.data!;
        await _localStore.cacheOffers(offers, etag: response.etag);
      }
      offlineMode = false;
      infoBanner = null;
    } catch (error) {
      offlineMode = true;
      infoBanner = _friendlyError(error);
    } finally {
      isLoadingOffers = false;
      notifyListeners();
    }
  }

  Future<void> loadOrgs({String? preferredOrgId}) async {
    isLoadingOrgs = true;
    notifyListeners();
    try {
      final fetched = await _repository.listOrgs();
      orgs = fetched.where((org) => org.isActiveMember).toList(growable: false);
      String? resolvedOrgId = preferredOrgId;
      if (resolvedOrgId == null || resolvedOrgId.trim().isEmpty) {
        final prefs = await SharedPreferences.getInstance();
        resolvedOrgId = prefs.getString(activeOrgPrefsKey);
      }
      if (!_hasOrg(resolvedOrgId)) {
        resolvedOrgId = orgs.isNotEmpty ? orgs.first.id : null;
      }
      activeOrgId = resolvedOrgId;
      await _persistActiveOrg(resolvedOrgId);
      offlineMode = false;
    } catch (error) {
      infoBanner = _friendlyError(error);
      offlineMode = true;
    } finally {
      isLoadingOrgs = false;
      notifyListeners();
    }
  }

  Future<void> selectOrg(String? orgId) async {
    if (!_hasOrg(orgId)) {
      return;
    }
    activeOrgId = orgId;
    await _persistActiveOrg(orgId);
    await refreshActiveOrgPurchases();
    notifyListeners();
  }

  Future<void> refreshActiveOrgPurchases() async {
    if (!hasActiveOrg || !canManageBilling) {
      activeOrgPurchases = <MarketplacePurchaseSnapshot>[];
      notifyListeners();
      return;
    }
    isLoadingBilling = true;
    notifyListeners();
    try {
      activeOrgPurchases = await _repository.fetchOrgPurchases(activeOrgId!);
      offlineMode = false;
    } catch (error) {
      infoBanner = _friendlyError(error);
      offlineMode = true;
    } finally {
      isLoadingBilling = false;
      notifyListeners();
    }
  }

  Future<String?> createInvite({
    required String email,
    required String role,
  }) async {
    final orgId = activeOrgId;
    if (orgId == null || orgId.trim().isEmpty) {
      infoBanner = 'Select a team before sending invites.';
      notifyListeners();
      return null;
    }
    try {
      final invite = await _repository.createOrgInvite(
        orgId: orgId,
        email: email,
        role: role,
      );
      infoBanner = null;
      return invite.token;
    } catch (error) {
      infoBanner = _friendlyError(error);
      notifyListeners();
      rethrow;
    }
  }

  Future<void> acceptInvite(String token) async {
    try {
      final accepted = await _repository.acceptOrgInvite(token);
      if (accepted == null) {
        return;
      }
      await loadOrgs(preferredOrgId: accepted.id);
      await refreshActiveOrgPurchases();
      infoBanner = null;
    } catch (error) {
      infoBanner = _friendlyError(error);
      notifyListeners();
      rethrow;
    }
  }

  Future<void> loadPaywall(String offerId) async {
    isLoadingPaywall = true;
    notifyListeners();
    try {
      final response = await _repository.fetchPaywallCopy(offerId);
      if (response.data != null) {
        paywallCopy = response.data;
      } else {
        paywallCopy = _fallbackPaywall(offerId);
      }
      offlineMode = false;
      infoBanner = null;
    } catch (error) {
      offlineMode = true;
      paywallCopy = _fallbackPaywall(offerId);
      infoBanner = _friendlyError(error);
    } finally {
      isLoadingPaywall = false;
      notifyListeners();
    }
  }

  Future<String> submitSeats({
    required String offerId,
    required int seatCount,
    required List<MarketplaceAssignment> assignments,
  }) async {
    isSubmittingSeats = true;
    infoBanner = null;
    notifyListeners();

    final idempotencyKey = await _checkoutIdempotencyKey(
      offerId: offerId,
      seatCount: seatCount,
      assignments: assignments,
    );
    final pendingPurchaseId = 'pending-$idempotencyKey';

    try {
      final created = await _repository.createPurchase(
        offerId: offerId,
        seatCount: seatCount,
        assignments: assignments,
        idempotencyKey: idempotencyKey,
        orgId: activeOrgId,
      );
      purchase = created;
      _activePurchaseId = created.purchaseId;
      await _localStore.cachePurchase(created);
      await _localStore.setMeta(
        'idempotencyPurchase:$idempotencyKey',
        created.purchaseId,
      );
      await refreshTimeline(created.purchaseId);
      if (hasActiveOrg && canManageBilling) {
        await refreshActiveOrgPurchases();
      }
      offlineMode = false;
      return created.purchaseId;
    } catch (error) {
      try {
        final restored = await _repository.restorePurchase(idempotencyKey);
        if (restored != null) {
          purchase = restored;
          _activePurchaseId = restored.purchaseId;
          await _localStore.cachePurchase(restored);
          await _localStore.setMeta(
            'idempotencyPurchase:$idempotencyKey',
            restored.purchaseId,
          );
          await refreshTimeline(restored.purchaseId);
          if (hasActiveOrg && canManageBilling) {
            await refreshActiveOrgPurchases();
          }
          offlineMode = false;
          return restored.purchaseId;
        }
      } catch (_) {
        // Continue into queued offline flow.
      }
      offlineMode = true;
      final pending = MarketplacePurchaseSnapshot(
        purchaseId: pendingPurchaseId,
        offerId: offerId,
        seatCount: seatCount,
        status: 'pending_sync',
        createdAt: DateTime.now().toUtc(),
        totalAmount: _offerPrice(offerId),
        currency: _offerCurrency(offerId),
        version: 1,
        assignmentsVersion: 1,
        assignments: assignments,
      );
      purchase = pending;
      _activePurchaseId = pendingPurchaseId;
      await _localStore.cachePurchase(pending);
      await _localStore
          .mergeTimeline(pendingPurchaseId, <MarketplaceTimelineEvent>[
            MarketplaceTimelineEvent(
              type: 'PURCHASE_QUEUED',
              title: 'Purchase queued',
              description: 'Will sync automatically when network is available.',
              timestamp: DateTime.now().toUtc(),
              status: 'warning',
            ),
          ]);
      await enqueueOutbox(
        MarketplaceOutboxItem(
          id: newRequestId(),
          type: MarketplaceOutboxType.createPurchase,
          purchaseId: pendingPurchaseId,
          idempotencyKey: idempotencyKey,
          payload: <String, dynamic>{
            'offerId': offerId,
            'seatCount': seatCount,
            'org_id': activeOrgId,
            'assignments': assignments
                .map((assignment) => assignment.toJson())
                .toList(growable: false),
            'pendingPurchaseId': pendingPurchaseId,
          },
          status: MarketplaceOutboxStatus.queued,
          attempts: 0,
          createdAt: DateTime.now().toUtc(),
        ),
      );
      await flushOutbox();
      infoBanner = _friendlyError(error);
      return pendingPurchaseId;
    } finally {
      isSubmittingSeats = false;
      notifyListeners();
    }
  }

  Future<void> loadPurchase(String purchaseId) async {
    _activePurchaseId = purchaseId;
    final resolvedPurchaseId = await resolvePurchaseId(purchaseId);
    purchase = await _localStore.readPurchase(resolvedPurchaseId);
    timeline = await _localStore.readTimeline(resolvedPurchaseId);
    notifyListeners();

    try {
      final etag = await _localStore.getMeta(
        'purchaseEtag:$resolvedPurchaseId',
      );
      final response = await _repository.fetchPurchase(
        resolvedPurchaseId,
        ifNoneMatch: etag,
      );
      if (!response.notModified && response.data != null) {
        purchase = response.data;
        await _localStore.cachePurchase(response.data!, etag: response.etag);
        final purchaseOrgId = response.data!.orgId;
        if (_hasOrg(purchaseOrgId) && purchaseOrgId != activeOrgId) {
          activeOrgId = purchaseOrgId;
          await _persistActiveOrg(purchaseOrgId);
        }
      }
      offlineMode = false;
      infoBanner = null;
      await refreshTimeline(resolvedPurchaseId);
      if (hasActiveOrg && canManageBilling) {
        await refreshActiveOrgPurchases();
      }
    } catch (error) {
      offlineMode = true;
      infoBanner = _friendlyError(error);
    } finally {
      notifyListeners();
    }
  }

  Future<void> refreshTimeline(String purchaseId) async {
    final resolvedPurchaseId = await resolvePurchaseId(purchaseId);
    final sinceRaw = await _localStore.getMeta(
      'lastTimelineAt:$resolvedPurchaseId',
    );
    final sinceUtc = DateTime.tryParse((sinceRaw ?? '').trim())?.toUtc();
    final etag = await _localStore.getMeta('timelineEtag:$resolvedPurchaseId');
    try {
      final response = await _repository.fetchTimeline(
        resolvedPurchaseId,
        sinceUtc: sinceUtc,
        limit: 200,
        ifNoneMatch: sinceUtc == null ? etag : null,
      );
      if (!response.notModified && response.data != null) {
        await _localStore.mergeTimeline(
          resolvedPurchaseId,
          response.data!,
          latestEventAt: response.latestEventAt,
          cursor: response.cursor,
        );
        if (response.etag != null && response.etag!.trim().isNotEmpty) {
          await _localStore.setMeta(
            'timelineEtag:$resolvedPurchaseId',
            response.etag!.trim(),
          );
        }
      }
      timeline = await _localStore.readTimeline(resolvedPurchaseId);
      offlineMode = false;
      infoBanner = null;
    } catch (error) {
      offlineMode = true;
      infoBanner = _friendlyError(error);
    } finally {
      notifyListeners();
    }
  }

  Future<void> enqueueSeatUpdate({
    required String purchaseId,
    required int seatCount,
    required int baseVersion,
  }) async {
    final resolvedPurchaseId = await resolvePurchaseId(purchaseId);
    final id = newRequestId();
    await enqueueOutbox(
      MarketplaceOutboxItem(
        id: id,
        type: MarketplaceOutboxType.updateSeats,
        purchaseId: resolvedPurchaseId,
        idempotencyKey: newIdempotencyKey(),
        payload: <String, dynamic>{'seatCount': seatCount},
        baseVersion: baseVersion,
        status: MarketplaceOutboxStatus.queued,
        attempts: 0,
        createdAt: DateTime.now().toUtc(),
      ),
    );
    if (purchase != null && purchase!.purchaseId == resolvedPurchaseId) {
      purchase = MarketplacePurchaseSnapshot(
        purchaseId: purchase!.purchaseId,
        offerId: purchase!.offerId,
        seatCount: seatCount,
        status: purchase!.status,
        createdAt: purchase!.createdAt,
        totalAmount: purchase!.totalAmount,
        currency: purchase!.currency,
        version: purchase!.version,
        assignmentsVersion: purchase!.assignmentsVersion,
        assignments: purchase!.assignments,
        provider: purchase!.provider,
        providerRef: purchase!.providerRef,
      );
      await _localStore.cachePurchase(purchase!);
    }
    await flushOutbox();
    notifyListeners();
  }

  Future<void> enqueueAssignmentsUpdate({
    required String purchaseId,
    required List<MarketplaceAssignment> assignments,
    required int baseVersion,
  }) async {
    final resolvedPurchaseId = await resolvePurchaseId(purchaseId);
    await enqueueOutbox(
      MarketplaceOutboxItem(
        id: newRequestId(),
        type: MarketplaceOutboxType.updateAssignments,
        purchaseId: resolvedPurchaseId,
        idempotencyKey: newIdempotencyKey(),
        payload: <String, dynamic>{
          'assignments': assignments
              .map((assignment) => assignment.toJson())
              .toList(growable: false),
        },
        baseVersion: baseVersion,
        status: MarketplaceOutboxStatus.queued,
        attempts: 0,
        createdAt: DateTime.now().toUtc(),
      ),
    );
    await flushOutbox();
    notifyListeners();
  }

  Future<void> enqueueOutbox(MarketplaceOutboxItem item) async {
    await _localStore.upsertOutboxItem(item);
    await _refreshPendingCount();
    notifyListeners();
  }

  Future<void> startSyncLoop({String? purchaseId}) async {
    _activePurchaseId = purchaseId ?? _activePurchaseId;
    _syncTimer?.cancel();
    _syncTimer = Timer.periodic(_syncInterval, (_) {
      unawaited(flushOutbox());
      final currentPurchaseId = _activePurchaseId;
      if (currentPurchaseId != null && currentPurchaseId.isNotEmpty) {
        unawaited(loadPurchase(currentPurchaseId));
      }
    });
    await flushOutbox();
  }

  void stopSyncLoop() {
    _syncTimer?.cancel();
    _syncTimer = null;
  }

  Future<void> flushOutbox() async {
    if (isSyncing) {
      return;
    }
    isSyncing = true;
    notifyListeners();

    try {
      final dueItems = await _localStore.readDueOutboxItems();
      for (final item in dueItems) {
        await _localStore.updateOutboxStatus(
          id: item.id,
          status: MarketplaceOutboxStatus.sending,
          attempts: item.attempts,
        );
        try {
          await _processOutboxItem(item);
          await _localStore.deleteOutboxItem(item.id);
          offlineMode = false;
        } on ApiException catch (error) {
          if (item.type == MarketplaceOutboxType.createPurchase) {
            try {
              final restored = await _repository.restorePurchase(
                item.idempotencyKey,
              );
              if (restored != null) {
                await _localStore.cachePurchase(restored);
                await _localStore.setMeta(
                  'idempotencyPurchase:${item.idempotencyKey}',
                  restored.purchaseId,
                );
                await _localStore.deleteOutboxItem(item.id);
                continue;
              }
            } catch (_) {
              // Continue into retry/dead policy.
            }
          }
          if (error.statusCode == 409 && error.code == 'VERSION_CONFLICT') {
            await _rebaseOutboxItem(item, error);
            continue;
          }
          if (_shouldRetry(error)) {
            await _retryOutboxItem(item, _friendlyError(error));
            continue;
          }
          await _markOutboxDead(item, _friendlyError(error));
        } catch (error) {
          await _retryOutboxItem(item, _friendlyError(error));
        }
      }
      await _refreshPendingCount();
    } finally {
      isSyncing = false;
      notifyListeners();
    }
  }

  Future<void> _processOutboxItem(MarketplaceOutboxItem item) async {
    switch (item.type) {
      case MarketplaceOutboxType.createPurchase:
        final assignments =
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
        final created = await _repository.createPurchase(
          offerId: item.payload['offerId']?.toString() ?? '',
          seatCount: (item.payload['seatCount'] as num?)?.toInt() ?? 1,
          assignments: assignments,
          idempotencyKey: item.idempotencyKey,
          orgId: item.payload['org_id']?.toString(),
        );
        await _localStore.cachePurchase(created);
        await _localStore.setMeta(
          'idempotencyPurchase:${item.idempotencyKey}',
          created.purchaseId,
        );
        final pendingPurchaseId = item.payload['pendingPurchaseId']?.toString();
        if (pendingPurchaseId != null && pendingPurchaseId.isNotEmpty) {
          await _localStore.setMeta(
            'pendingAlias:$pendingPurchaseId',
            created.purchaseId,
          );
        }
        await refreshTimeline(created.purchaseId);
        break;
      case MarketplaceOutboxType.updateSeats:
        final purchaseId = item.purchaseId ?? '';
        if (purchaseId.isEmpty) {
          throw StateError('missing_purchase_id_for_update_seats');
        }
        final updated = await _repository.updateSeats(
          purchaseId: purchaseId,
          seatCount: (item.payload['seatCount'] as num?)?.toInt() ?? 1,
          baseVersion: item.baseVersion ?? 1,
        );
        await _localStore.cachePurchase(updated);
        await refreshTimeline(updated.purchaseId);
        break;
      case MarketplaceOutboxType.updateAssignments:
        final purchaseId = item.purchaseId ?? '';
        if (purchaseId.isEmpty) {
          throw StateError('missing_purchase_id_for_update_assignments');
        }
        final assignments =
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
        final updated = await _repository.updateAssignments(
          purchaseId: purchaseId,
          assignments: assignments,
          baseVersion: item.baseVersion ?? 1,
        );
        await _localStore.cachePurchase(updated);
        await refreshTimeline(updated.purchaseId);
        break;
      case MarketplaceOutboxType.changePlan:
        final purchaseId = item.purchaseId ?? '';
        if (purchaseId.isEmpty) {
          throw StateError('missing_purchase_id_for_change_plan');
        }
        final updated = await _repository.changePlan(
          purchaseId: purchaseId,
          offerId: item.payload['offerId']?.toString() ?? '',
          baseVersion: item.baseVersion ?? 1,
          idempotencyKey: item.idempotencyKey,
        );
        await _localStore.cachePurchase(updated);
        await refreshTimeline(updated.purchaseId);
        break;
    }
  }

  Future<void> _retryOutboxItem(
    MarketplaceOutboxItem item,
    String reason,
  ) async {
    final attempts = item.attempts + 1;
    final backoffMs = attempts == 1 ? 250 : (attempts == 2 ? 750 : 2000);
    final nextRetryAt = DateTime.now().toUtc().add(
      Duration(milliseconds: backoffMs),
    );
    await _localStore.updateOutboxStatus(
      id: item.id,
      status: attempts >= 6
          ? MarketplaceOutboxStatus.dead
          : MarketplaceOutboxStatus.failed,
      attempts: attempts,
      nextRetryAt: attempts >= 6 ? null : nextRetryAt,
      lastError: reason,
    );
    offlineMode = true;
    infoBanner = reason;
  }

  Future<void> _markOutboxDead(MarketplaceOutboxItem item, String reason) {
    return _localStore.updateOutboxStatus(
      id: item.id,
      status: MarketplaceOutboxStatus.dead,
      attempts: item.attempts + 1,
      nextRetryAt: null,
      lastError: reason,
    );
  }

  Future<void> _rebaseOutboxItem(
    MarketplaceOutboxItem item,
    ApiException error,
  ) async {
    final envelope = error.envelope ?? const <String, dynamic>{};
    final data = envelope['data'];
    final latestRaw = data is Map ? data['latest'] : null;
    if (latestRaw is! Map) {
      await _markOutboxDead(item, 'Conflict without latest snapshot');
      return;
    }
    final latest = MarketplacePurchaseSnapshot.fromJson(
      latestRaw.map(
        (key, value) => MapEntry<String, dynamic>(key.toString(), value),
      ),
    );
    await _localStore.cachePurchase(latest);
    if (item.type == MarketplaceOutboxType.updateSeats) {
      final seatCount = (item.payload['seatCount'] as num?)?.toInt() ?? 0;
      if (seatCount < 1 || seatCount > 50) {
        await _markOutboxDead(item, 'Changes could not be applied');
        infoBanner = 'Changes could not be applied. Tap to review.';
        return;
      }
    }
    await _localStore.updateOutboxStatus(
      id: item.id,
      status: MarketplaceOutboxStatus.queued,
      attempts: item.attempts,
      baseVersion: latest.version,
      nextRetryAt: DateTime.now().toUtc(),
      lastError: null,
    );
    infoBanner = 'Changes were rebased on latest data and re-queued.';
  }

  Future<String> resolvePurchaseId(String purchaseId) async {
    if (purchaseId.startsWith('pending-')) {
      final alias = await _localStore.getMeta('pendingAlias:$purchaseId');
      if (alias != null && alias.trim().isNotEmpty) {
        return alias.trim();
      }
    }
    return purchaseId;
  }

  bool _shouldRetry(ApiException error) {
    if (error.statusCode >= 500) {
      return true;
    }
    return false;
  }

  Future<String> _checkoutIdempotencyKey({
    required String offerId,
    required int seatCount,
    required List<MarketplaceAssignment> assignments,
  }) async {
    final sortedAssignments =
        assignments
            .map((assignment) => assignment.toJson())
            .toList(growable: true)
          ..sort((left, right) {
            final li = (left['seatIndex'] as num?)?.toInt() ?? 0;
            final ri = (right['seatIndex'] as num?)?.toInt() ?? 0;
            return li.compareTo(ri);
          });
    final hashSource = jsonEncode(<String, dynamic>{
      'offerId': offerId,
      'seatCount': seatCount,
      'assignments': sortedAssignments,
    });
    final key = 'checkoutIdempotency:$hashSource';
    final existing = await _localStore.getMeta(key);
    if (existing != null && existing.trim().isNotEmpty) {
      return existing.trim();
    }
    final created = newIdempotencyKey();
    await _localStore.setMeta(key, created);
    return created;
  }

  int _offerPrice(String offerId) {
    for (final offer in offers) {
      if (offer.id == offerId) {
        return offer.price;
      }
    }
    return 0;
  }

  String _offerCurrency(String offerId) {
    for (final offer in offers) {
      if (offer.id == offerId) {
        return offer.currency;
      }
    }
    return 'NGN';
  }

  MarketplacePaywallCopy _fallbackPaywall(String offerId) {
    MarketplaceOffer? offer;
    for (final entry in offers) {
      if (entry.id == offerId) {
        offer = entry;
        break;
      }
    }
    return MarketplacePaywallCopy(
      offerId: offerId,
      headline: 'Confirm ${offer?.title ?? 'Plan'}',
      subhead: offer?.subtitle ?? 'You can continue offline and sync later.',
      bullets:
          offer?.perks ?? const <String>['Seat and plan changes are tracked'],
      legalText: 'Charges are subject to network confirmation.',
    );
  }

  String _friendlyError(Object error) {
    if (error is ApiException) {
      return error.toDisplayMessage();
    }
    return error.toString();
  }

  Future<void> _refreshPendingCount() async {
    final all = await _localStore.readAllOutboxItems();
    pendingOutboxCount = all
        .where(
          (item) =>
              item.status != MarketplaceOutboxStatus.acked &&
              item.status != MarketplaceOutboxStatus.dead,
        )
        .length;
  }

  bool _hasOrg(String? orgId) {
    final normalized = orgId?.trim() ?? '';
    if (normalized.isEmpty) {
      return false;
    }
    for (final org in orgs) {
      if (org.id == normalized) {
        return true;
      }
    }
    return false;
  }

  Future<void> _persistActiveOrg(String? orgId) async {
    final prefs = await SharedPreferences.getInstance();
    final normalized = orgId?.trim() ?? '';
    if (normalized.isEmpty) {
      await prefs.remove(activeOrgPrefsKey);
      return;
    }
    await prefs.setString(activeOrgPrefsKey, normalized);
  }

  @override
  void dispose() {
    _syncTimer?.cancel();
    unawaited(_localStore.close());
    super.dispose();
  }
}
