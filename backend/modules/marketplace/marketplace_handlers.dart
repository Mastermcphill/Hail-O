import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:shelf/shelf.dart';
import 'package:uuid/uuid.dart';

import '../../infra/request_context.dart';
import '../../server/http_utils.dart';
import 'marketplace_entitlement_service.dart';
import 'marketplace_revenue_service.dart';
import '../payments/payment_service.dart';
import 'marketplace_offer_repository.dart';
import 'org_rbac.dart';
import 'org_repository.dart';

class MarketplaceHandlers {
  MarketplaceHandlers({
    required MarketplaceOfferRepository offerRepository,
    PaymentService? paymentService,
    MarketplaceEntitlementService? entitlementService,
    MarketplaceRevenueService? revenueService,
    OrgRepository? orgRepository,
    Uuid? uuid,
  }) : _offerRepository = offerRepository,
       _paymentService = paymentService,
       _entitlementService = entitlementService,
       _revenueService = revenueService ?? MarketplaceRevenueService(),
       _orgRepository = orgRepository,
       _uuid = uuid ?? const Uuid();

  final MarketplaceOfferRepository _offerRepository;
  final PaymentService? _paymentService;
  final MarketplaceEntitlementService? _entitlementService;
  final MarketplaceRevenueService _revenueService;
  final OrgRepository? _orgRepository;
  final Uuid _uuid;
  final Map<String, String> _orgIdByPurchaseId = <String, String>{};
  final Map<String, String> _ownerUserIdByPurchaseId = <String, String>{};
  final Map<String, String> _purchaseIdByOrgAndIdempotency = <String, String>{};
  final Map<String, int> _versionByPurchaseId = <String, int>{};

  Future<Response> listOffers(Request request) async {
    final pagination = _parsePaginationOptions(
      request: request,
      defaultLimit: 20,
      maxLimit: 100,
    );
    if (pagination.errorResponse != null) {
      return pagination.errorResponse!;
    }

    final offers = await _offerRepository.listActiveOffers();
    final allOffers = offers
        .map(
          (offer) => <String, Object?>{
            'id': offer.id,
            'title': offer.title,
            'subtitle': offer.description,
            'price': offer.priceMinor,
            'currency': offer.currency,
            'interval': offer.interval,
            'perks': offer.perks,
          },
        )
        .toList(growable: false);
    final start = pagination.offset >= allOffers.length
        ? allOffers.length
        : pagination.offset;
    final endExclusive = start + pagination.limit > allOffers.length
        ? allOffers.length
        : start + pagination.limit;
    final data = allOffers.sublist(start, endExclusive);
    final nextCursor = endExclusive < allOffers.length
        ? _encodeCursor(endExclusive)
        : null;
    final etag = _etagForPayload(<String, Object?>{
      'offset': start,
      'limit': pagination.limit,
      'next_cursor': nextCursor,
      'data': data,
    });
    final ifNoneMatch = request.headers['if-none-match'];
    if (ifNoneMatch != null &&
        _matchesAnyEtag(ifNoneMatch: ifNoneMatch, etag: etag)) {
      return Response.notModified(headers: <String, String>{'etag': etag});
    }
    return _ok(
      request,
      data: data,
      headers: <String, String>{'etag': etag},
      extra: nextCursor == null
          ? null
          : <String, Object?>{'next_cursor': nextCursor},
    );
  }

  Future<Response> listTimeline(Request request) async {
    final userId = _requireUserId(request);
    if (userId == null) {
      return _error(
        request,
        401,
        errorCode: 'UNAUTHORIZED',
        message: 'Bearer token required',
      );
    }
    final pagination = _parsePaginationOptions(
      request: request,
      defaultLimit: 20,
      maxLimit: 100,
    );
    if (pagination.errorResponse != null) {
      return pagination.errorResponse!;
    }
    final activeOrgIds = <String>{};
    final orgRepository = _orgRepository;
    if (orgRepository != null) {
      activeOrgIds.addAll(await orgRepository.listActiveOrgIdsForUser(userId));
    }

    final timelineEvents = <Map<String, Object?>>[];
    final purchaseIds = _ownerUserIdByPurchaseId.keys.toList(growable: false)
      ..sort();
    for (final purchaseId in purchaseIds) {
      final ownerUserId = _ownerUserIdByPurchaseId[purchaseId];
      if (ownerUserId == null || ownerUserId.trim().isEmpty) {
        continue;
      }
      final orgId = (_orgIdByPurchaseId[purchaseId] ?? ownerUserId).trim();
      final isOwner = ownerUserId == userId;
      final inActiveOrg = orgId == userId || activeOrgIds.contains(orgId);
      if (!isOwner && !inActiveOrg) {
        continue;
      }
      final events = await _offerRepository.listTimelineEvents(
        userId: ownerUserId,
        purchaseId: purchaseId,
        limit: 100,
      );
      for (final event in events) {
        timelineEvents.add(
          _timelineEventPayload(event: event, purchaseId: purchaseId),
        );
      }
    }

    timelineEvents.sort((left, right) {
      final leftTimestamp = _timestampSortValue(left['timestamp']);
      final rightTimestamp = _timestampSortValue(right['timestamp']);
      final timestampCompare = rightTimestamp.compareTo(leftTimestamp);
      if (timestampCompare != 0) {
        return timestampCompare;
      }
      final purchaseCompare = (left['purchase_id'] as String).compareTo(
        right['purchase_id'] as String,
      );
      if (purchaseCompare != 0) {
        return purchaseCompare;
      }
      return (left['type'] as String).compareTo(right['type'] as String);
    });

    final start = pagination.offset >= timelineEvents.length
        ? timelineEvents.length
        : pagination.offset;
    final endExclusive = start + pagination.limit > timelineEvents.length
        ? timelineEvents.length
        : start + pagination.limit;
    final page = timelineEvents
        .sublist(start, endExclusive)
        .map((event) => Map<String, Object?>.from(event))
        .toList(growable: false);
    final nextCursor = endExclusive < timelineEvents.length
        ? _encodeCursor(endExclusive)
        : null;
    final etag = _etagForPayload(<String, Object?>{
      'offset': start,
      'limit': pagination.limit,
      'next_cursor': nextCursor,
      'events': page,
    });
    final ifNoneMatch = request.headers['if-none-match'];
    if (ifNoneMatch != null &&
        _matchesAnyEtag(ifNoneMatch: ifNoneMatch, etag: etag)) {
      return Response.notModified(headers: <String, String>{'etag': etag});
    }
    return _ok(
      request,
      data: page,
      headers: <String, String>{'etag': etag},
      extra: nextCursor == null
          ? null
          : <String, Object?>{'next_cursor': nextCursor},
    );
  }

  Future<Response> getOfferPaywall(Request request, String offerId) async {
    final offer = await _offerRepository.findActiveOfferById(offerId);
    if (offer == null) {
      return _error(
        request,
        404,
        errorCode: 'NOT_FOUND',
        message: 'Offer not found',
      );
    }

    return _ok(
      request,
      data: <String, Object?>{
        'offerId': offer.id,
        'headline': 'Secure this ${offer.title} offer now',
        'subhead':
            'Connection fee confirms your driver match and seat capacity.',
        'bullets': <String>[
          'Connection fee reserves your selected capacity instantly.',
          'Final routing and dispatch happen immediately after seat confirmation.',
          if (offer.perks.isNotEmpty)
            'Offer highlights: ${offer.perks.join(', ')}',
        ],
        'legalText':
            'By continuing, you agree to marketplace terms and ride matching policies.',
      },
    );
  }

  Future<Response> createPurchase(Request request) async {
    final body = await _readBodyOrValidationError(request);
    if (body.response != null) {
      return body.response!;
    }

    final userId = _requireUserId(request);
    if (userId == null) {
      return _error(
        request,
        401,
        errorCode: 'UNAUTHORIZED',
        message: 'Bearer token required',
      );
    }

    final payload = body.payload!;
    final offerId =
        (payload['offerId'] as String?)?.trim() ??
        (payload['offer_id'] as String?)?.trim() ??
        '';
    final seatCount =
        _toInt(payload['seatCount']) ?? _toInt(payload['seat_count']);
    final orgId = _resolveOrgId(payload: payload, userId: userId);
    final idempotencyKey = (request.headers['idempotency-key'] ?? '').trim();

    if (idempotencyKey.isEmpty) {
      return _error(
        request,
        400,
        errorCode: 'MISSING_IDEMPOTENCY_KEY',
        message: 'Idempotency-Key header is required',
      );
    }

    if (offerId.isEmpty || seatCount == null || seatCount < 1) {
      return _error(
        request,
        400,
        errorCode: 'VALIDATION_ERROR',
        message: 'offerId and seatCount>=1 are required',
      );
    }

    try {
      await _revenueService.assertMutationAllowed(
        userId: userId,
        orgId: orgId,
        action: 'create_purchase',
      );
      var purchase = await _offerRepository.createOrGetPurchase(
        userId: userId,
        offerId: offerId,
        seatCount: seatCount,
        idempotencyKey: idempotencyKey,
        provider: _paymentService?.providerName ?? 'manual',
      );
      final paymentService = _paymentService;
      if (paymentService != null) {
        await paymentService.createCheckoutOrIntent(purchase: purchase);
        final refreshed = await _offerRepository.findPurchaseById(
          userId: userId,
          purchaseId: purchase.id,
        );
        if (refreshed != null) {
          purchase = refreshed;
        }
      }
      final entitlementService = _entitlementService;
      if (entitlementService != null) {
        await entitlementService.syncPurchaseEntitlements(
          purchase: purchase,
          reason: 'purchase_create',
        );
      }
      final invoice = await _revenueService.createInvoice(
        orgId: orgId,
        userId: userId,
        purchaseId: purchase.id,
        offerId: offerId,
        seats: seatCount,
      );
      _recordPurchaseAccess(
        purchaseId: purchase.id,
        ownerUserId: purchase.userId,
        orgId: orgId,
        idempotencyKey: idempotencyKey,
      );
      final version = _currentVersion(purchase.id);
      final purchasePayload = await _buildPurchasePayload(
        purchase: purchase,
        ownerUserId: purchase.userId,
        orgId: orgId,
        version: version,
      );
      return _ok(
        request,
        data: <String, Object?>{...purchasePayload, 'invoice': invoice},
        headers: <String, String>{
          'x-idempotency-key': idempotencyKey,
          'x-marketplace-purchase-id': purchase.id,
        },
      );
    } on MarketplaceRevenueException catch (error) {
      return _error(
        request,
        error.statusCode,
        errorCode: error.code,
        message: error.message,
      );
    } on MarketplaceRepositoryStateException catch (error) {
      if (error.code == 'offer_not_found') {
        return _error(
          request,
          404,
          errorCode: 'NOT_FOUND',
          message: 'Offer not found',
        );
      }
      return _error(request, 409, errorCode: 'CONFLICT', message: error.code);
    } catch (_) {
      return _error(
        request,
        500,
        errorCode: 'INTERNAL_ERROR',
        message: 'Unable to create purchase',
      );
    }
  }

  Future<Response> restorePurchase(Request request) async {
    final idempotencyKey = (request.url.queryParameters['idempotencyKey'] ?? '')
        .trim();
    if (idempotencyKey.isEmpty) {
      return _error(
        request,
        400,
        errorCode: 'VALIDATION_ERROR',
        message: 'idempotencyKey is required',
      );
    }
    return _restorePurchaseByIdempotencyKey(request, idempotencyKey);
  }

  Future<Response> restorePurchasePost(Request request) async {
    final body = await _readBodyOrValidationError(request);
    if (body.response != null) {
      return body.response!;
    }
    final payload = body.payload!;
    final idempotencyKey =
        (payload['idempotencyKey'] as String?)?.trim() ??
        (payload['idempotency_key'] as String?)?.trim() ??
        (request.url.queryParameters['idempotencyKey'] ?? '').trim();
    if (idempotencyKey.isEmpty) {
      return _error(
        request,
        400,
        errorCode: 'VALIDATION_ERROR',
        message: 'idempotencyKey is required',
      );
    }
    return _restorePurchaseByIdempotencyKey(request, idempotencyKey);
  }

  Future<Response> _restorePurchaseByIdempotencyKey(
    Request request,
    String idempotencyKey,
  ) async {
    final userId = _requireUserId(request);
    if (userId == null) {
      return _error(
        request,
        401,
        errorCode: 'UNAUTHORIZED',
        message: 'Bearer token required',
      );
    }

    var purchase = await _offerRepository.findPurchaseByIdempotencyKey(
      userId: userId,
      idempotencyKey: idempotencyKey,
    );
    var resolvedOrgId = purchase == null
        ? null
        : _orgIdByPurchaseId[purchase.id];
    if (purchase == null) {
      final orgRepository = _orgRepository;
      if (orgRepository != null) {
        final activeOrgIds = await orgRepository.listActiveOrgIdsForUser(
          userId,
        );
        for (final orgId in activeOrgIds) {
          final candidatePurchaseId =
              _purchaseIdByOrgAndIdempotency['$orgId::$idempotencyKey'];
          if (candidatePurchaseId == null) {
            continue;
          }
          final ownerUserId = _ownerUserIdByPurchaseId[candidatePurchaseId];
          if (ownerUserId == null) {
            continue;
          }
          final candidate = await _offerRepository.findPurchaseById(
            userId: ownerUserId,
            purchaseId: candidatePurchaseId,
          );
          if (candidate == null) {
            continue;
          }
          purchase = candidate;
          resolvedOrgId = orgId;
          break;
        }
      }
    }
    if (purchase == null) {
      return _error(
        request,
        404,
        errorCode: 'NOT_FOUND',
        message: 'Purchase not found for idempotency key',
      );
    }
    _recordPurchaseAccess(
      purchaseId: purchase.id,
      ownerUserId: purchase.userId,
      orgId: resolvedOrgId ?? purchase.userId,
      idempotencyKey: idempotencyKey,
    );
    final payload = await _buildPurchasePayload(
      purchase: purchase,
      ownerUserId: purchase.userId,
      orgId: resolvedOrgId ?? purchase.userId,
      version: _currentVersion(purchase.id),
    );

    return _ok(
      request,
      data: payload,
      headers: <String, String>{
        'x-idempotency-key': idempotencyKey,
        'x-marketplace-purchase-id': purchase.id,
      },
    );
  }

  Future<Response> getPurchase(Request request, String purchaseId) async {
    final userId = _requireUserId(request);
    if (userId == null) {
      return _error(
        request,
        401,
        errorCode: 'UNAUTHORIZED',
        message: 'Bearer token required',
      );
    }

    final purchaseAccess = _resolvePurchaseAccess(
      purchaseId: purchaseId,
      actingUserId: userId,
    );
    if (purchaseAccess == null) {
      return _error(
        request,
        404,
        errorCode: 'NOT_FOUND',
        message: 'Purchase not found',
      );
    }
    if (purchaseAccess.ownerUserId != userId &&
        !await _hasActiveOrgMembership(
          orgId: purchaseAccess.orgId,
          userId: userId,
        )) {
      return forbiddenOrgRole(request);
    }
    final purchase = await _offerRepository.findPurchaseById(
      userId: purchaseAccess.ownerUserId,
      purchaseId: purchaseId,
    );
    if (purchase == null) {
      return _error(
        request,
        404,
        errorCode: 'NOT_FOUND',
        message: 'Purchase not found',
      );
    }
    final payload = await _buildPurchasePayload(
      purchase: purchase,
      ownerUserId: purchaseAccess.ownerUserId,
      orgId: purchaseAccess.orgId,
      version: _currentVersion(purchaseId),
    );
    final etag = _etagForPayload(payload);
    final ifNoneMatch = request.headers['if-none-match'];
    if (ifNoneMatch != null &&
        _matchesAnyEtag(ifNoneMatch: ifNoneMatch, etag: etag)) {
      return Response.notModified(
        headers: <String, String>{
          'etag': etag,
          'x-marketplace-purchase-id': purchase.id,
        },
      );
    }

    return _ok(
      request,
      data: payload,
      headers: <String, String>{
        'etag': etag,
        'x-marketplace-purchase-id': purchase.id,
      },
    );
  }

  Future<Response> updateSeats(Request request, String purchaseId) async {
    final body = await _readBodyOrValidationError(request);
    if (body.response != null) {
      return body.response!;
    }
    final userId = _requireUserId(request);
    if (userId == null) {
      return _error(
        request,
        401,
        errorCode: 'UNAUTHORIZED',
        message: 'Bearer token required',
      );
    }

    final payload = body.payload!;
    final seatCount =
        _toInt(payload['seat_count']) ?? _toInt(payload['seatCount']);
    if (seatCount == null || seatCount < 1 || seatCount > 50) {
      return _error(
        request,
        400,
        errorCode: 'VALIDATION_ERROR',
        message: 'seat_count must be between 1 and 50',
      );
    }
    final purchaseAccess = _resolvePurchaseAccess(
      purchaseId: purchaseId,
      actingUserId: userId,
    );
    if (purchaseAccess == null) {
      return _error(
        request,
        404,
        errorCode: 'NOT_FOUND',
        message: 'Purchase not found',
      );
    }
    final roleError = await _authorizePurchaseMutation(
      request: request,
      purchaseAccess: purchaseAccess,
      actingUserId: userId,
      allowedOrgRoles: kOrgAdminRoles,
    );
    if (roleError != null) {
      return roleError;
    }
    final versionConflict = await _versionConflictResponse(
      request: request,
      purchaseId: purchaseId,
      purchaseAccess: purchaseAccess,
    );
    if (versionConflict != null) {
      return versionConflict;
    }

    try {
      await _revenueService.assertMutationAllowed(
        userId: userId,
        orgId: purchaseAccess.orgId,
        action: 'update_seats',
      );
      final purchase = await _offerRepository.updateSeatCount(
        userId: purchaseAccess.ownerUserId,
        purchaseId: purchaseId,
        seatCount: seatCount,
      );
      final entitlementService = _entitlementService;
      if (entitlementService != null) {
        await entitlementService.syncPurchaseEntitlements(
          purchase: purchase,
          reason: 'seat_count_changed',
        );
      }
      final version = _bumpVersion(purchase.id);
      final payload = await _buildPurchasePayload(
        purchase: purchase,
        ownerUserId: purchaseAccess.ownerUserId,
        orgId: purchaseAccess.orgId,
        version: version,
      );
      return _ok(
        request,
        data: payload,
        headers: <String, String>{'x-marketplace-purchase-id': purchase.id},
      );
    } on MarketplaceRevenueException catch (error) {
      return _error(
        request,
        error.statusCode,
        errorCode: error.code,
        message: error.message,
      );
    } on MarketplaceRepositoryStateException catch (error) {
      if (error.code == 'purchase_not_found') {
        return _error(
          request,
          404,
          errorCode: 'NOT_FOUND',
          message: 'Purchase not found',
        );
      }
      return _error(request, 409, errorCode: 'CONFLICT', message: error.code);
    }
  }

  Future<Response> updateAssignments(Request request, String purchaseId) async {
    final body = await _readBodyOrValidationError(request);
    if (body.response != null) {
      return body.response!;
    }
    final userId = _requireUserId(request);
    if (userId == null) {
      return _error(
        request,
        401,
        errorCode: 'UNAUTHORIZED',
        message: 'Bearer token required',
      );
    }

    final payload = body.payload!;
    final rawAssignments = payload['assignments'];
    if (rawAssignments is! List) {
      return _error(
        request,
        400,
        errorCode: 'VALIDATION_ERROR',
        message: 'assignments must be an array',
      );
    }
    final assignments = <MarketplaceSeatAssignmentInput>[];
    final parsedAssignments = <Map<String, Object?>>[];
    for (final item in rawAssignments) {
      if (item is! Map) {
        continue;
      }
      final map = Map<String, Object?>.from(
        item.map((key, value) => MapEntry(key.toString(), value)),
      );
      parsedAssignments.add(map);
      final seatIndex =
          _toInt(map['seatIndex']) ??
          _toInt(map['seat_index']) ??
          _toInt(map['seat_number']) ??
          0;
      assignments.add(
        MarketplaceSeatAssignmentInput(
          seatIndex: seatIndex,
          name: (map['name'] as String?)?.trim() ?? '',
          email: (map['email'] as String?)?.trim() ?? '',
        ),
      );
    }
    final purchaseAccess = _resolvePurchaseAccess(
      purchaseId: purchaseId,
      actingUserId: userId,
    );
    if (purchaseAccess == null) {
      return _error(
        request,
        404,
        errorCode: 'NOT_FOUND',
        message: 'Purchase not found',
      );
    }
    final roleError = await _authorizePurchaseMutation(
      request: request,
      purchaseAccess: purchaseAccess,
      actingUserId: userId,
      allowedOrgRoles: kOrgBillingRoles,
    );
    if (roleError != null) {
      return roleError;
    }
    final assigneeError = await _validateAssignmentAssignees(
      request: request,
      purchaseAccess: purchaseAccess,
      assignments: parsedAssignments,
    );
    if (assigneeError != null) {
      return assigneeError;
    }
    final versionConflict = await _versionConflictResponse(
      request: request,
      purchaseId: purchaseId,
      purchaseAccess: purchaseAccess,
    );
    if (versionConflict != null) {
      return versionConflict;
    }

    try {
      await _revenueService.assertMutationAllowed(
        userId: userId,
        orgId: purchaseAccess.orgId,
        action: 'update_assignments',
      );
      final purchase = await _offerRepository.replaceAssignments(
        userId: purchaseAccess.ownerUserId,
        purchaseId: purchaseId,
        assignments: assignments,
      );
      final version = _bumpVersion(purchase.id);
      final payload = await _buildPurchasePayload(
        purchase: purchase,
        ownerUserId: purchaseAccess.ownerUserId,
        orgId: purchaseAccess.orgId,
        version: version,
      );
      return _ok(
        request,
        data: payload,
        headers: <String, String>{'x-marketplace-purchase-id': purchase.id},
      );
    } on MarketplaceRevenueException catch (error) {
      return _error(
        request,
        error.statusCode,
        errorCode: error.code,
        message: error.message,
      );
    } on MarketplaceRepositoryStateException catch (error) {
      if (error.code == 'purchase_not_found') {
        return _error(
          request,
          404,
          errorCode: 'NOT_FOUND',
          message: 'Purchase not found',
        );
      }
      return _error(request, 409, errorCode: 'CONFLICT', message: error.code);
    }
  }

  Future<Response> changePlan(Request request, String purchaseId) async {
    final body = await _readBodyOrValidationError(request);
    if (body.response != null) {
      return body.response!;
    }
    final userId = _requireUserId(request);
    if (userId == null) {
      return _error(
        request,
        401,
        errorCode: 'UNAUTHORIZED',
        message: 'Bearer token required',
      );
    }
    final payload = body.payload!;
    final newOfferId =
        (payload['new_offer_id'] as String?)?.trim() ??
        (payload['newOfferId'] as String?)?.trim() ??
        (payload['offer_id'] as String?)?.trim() ??
        (payload['offerId'] as String?)?.trim() ??
        '';
    if (newOfferId.isEmpty) {
      return _error(
        request,
        400,
        errorCode: 'VALIDATION_ERROR',
        message: 'new_offer_id is required',
      );
    }
    final purchaseAccess = _resolvePurchaseAccess(
      purchaseId: purchaseId,
      actingUserId: userId,
    );
    if (purchaseAccess == null) {
      return _error(
        request,
        404,
        errorCode: 'NOT_FOUND',
        message: 'Purchase not found',
      );
    }
    final roleError = await _authorizePurchaseMutation(
      request: request,
      purchaseAccess: purchaseAccess,
      actingUserId: userId,
      allowedOrgRoles: kOrgBillingRoles,
    );
    if (roleError != null) {
      return roleError;
    }
    final versionConflict = await _versionConflictResponse(
      request: request,
      purchaseId: purchaseId,
      purchaseAccess: purchaseAccess,
    );
    if (versionConflict != null) {
      return versionConflict;
    }

    try {
      await _revenueService.assertMutationAllowed(
        userId: userId,
        orgId: purchaseAccess.orgId,
        action: 'change_plan',
      );
      final purchase = await _offerRepository.changePlan(
        userId: purchaseAccess.ownerUserId,
        purchaseId: purchaseId,
        newOfferId: newOfferId,
      );
      final entitlementService = _entitlementService;
      if (entitlementService != null) {
        await entitlementService.syncPurchaseEntitlements(
          purchase: purchase,
          reason: 'plan_changed',
        );
      }
      final version = _bumpVersion(purchase.id);
      final payload = await _buildPurchasePayload(
        purchase: purchase,
        ownerUserId: purchaseAccess.ownerUserId,
        orgId: purchaseAccess.orgId,
        version: version,
      );
      return _ok(
        request,
        data: payload,
        headers: <String, String>{'x-marketplace-purchase-id': purchase.id},
      );
    } on MarketplaceRevenueException catch (error) {
      return _error(
        request,
        error.statusCode,
        errorCode: error.code,
        message: error.message,
      );
    } on MarketplaceRepositoryStateException catch (error) {
      if (error.code == 'purchase_not_found' ||
          error.code == 'offer_not_found') {
        return _error(
          request,
          404,
          errorCode: 'NOT_FOUND',
          message: error.code == 'offer_not_found'
              ? 'Offer not found'
              : 'Purchase not found',
        );
      }
      return _error(request, 409, errorCode: 'CONFLICT', message: error.code);
    }
  }

  Future<Response> getTimeline(Request request, String purchaseId) async {
    final userId = _requireUserId(request);
    if (userId == null) {
      return _error(
        request,
        401,
        errorCode: 'UNAUTHORIZED',
        message: 'Bearer token required',
      );
    }

    final purchaseAccess = _resolvePurchaseAccess(
      purchaseId: purchaseId,
      actingUserId: userId,
    );
    if (purchaseAccess == null) {
      return _error(
        request,
        404,
        errorCode: 'NOT_FOUND',
        message: 'Purchase not found',
      );
    }
    if (purchaseAccess.ownerUserId != userId &&
        !await _hasActiveOrgMembership(
          orgId: purchaseAccess.orgId,
          userId: userId,
        )) {
      return forbiddenOrgRole(request);
    }
    final pagination = _parsePaginationOptions(
      request: request,
      defaultLimit: 20,
      maxLimit: 100,
    );
    if (pagination.errorResponse != null) {
      return pagination.errorResponse!;
    }
    var events = await _offerRepository.listTimelineEvents(
      userId: purchaseAccess.ownerUserId,
      purchaseId: purchaseId,
      limit: 100,
    );
    if (events.isEmpty) {
      final purchase = await _offerRepository.findPurchaseById(
        userId: purchaseAccess.ownerUserId,
        purchaseId: purchaseId,
      );
      if (purchase == null) {
        return _error(
          request,
          404,
          errorCode: 'NOT_FOUND',
          message: 'Purchase not found',
        );
      }
    }
    final sinceRaw = (request.url.queryParameters['since'] ?? '').trim();
    DateTime? sinceUtc;
    if (sinceRaw.isNotEmpty) {
      sinceUtc = DateTime.tryParse(sinceRaw)?.toUtc();
    }
    if (sinceUtc != null) {
      events = events
          .where((event) => event.createdAt.toUtc().isAfter(sinceUtc!))
          .toList(growable: false);
    }
    events.sort((left, right) {
      final timestampCompare = left.createdAt.toUtc().compareTo(
        right.createdAt.toUtc(),
      );
      if (timestampCompare != 0) {
        return timestampCompare;
      }
      return left.eventType.compareTo(right.eventType);
    });
    final start = pagination.offset >= events.length
        ? events.length
        : pagination.offset;
    final endExclusive = start + pagination.limit > events.length
        ? events.length
        : start + pagination.limit;
    final pagedEvents = events.sublist(start, endExclusive);
    final timelineEvents = pagedEvents
        .map((event) => _timelineEventPayload(event: event))
        .toList(growable: false);
    final nextCursor = endExclusive < events.length
        ? _encodeCursor(endExclusive)
        : null;
    final latestEventAt = events.isEmpty
        ? ''
        : events
              .map((event) => event.createdAt.toUtc())
              .reduce((left, right) => left.isAfter(right) ? left : right)
              .toIso8601String();
    final payload = <String, Object?>{
      'purchase_id': purchaseId,
      'latest_event_at': latestEventAt,
      'events': timelineEvents,
    };
    final etag = _etagForPayload(<Object?>[
      purchaseId,
      latestEventAt,
      timelineEvents.length,
      sinceRaw,
      start,
      pagination.limit,
      nextCursor,
    ]);
    final ifNoneMatch = request.headers['if-none-match'];
    if (ifNoneMatch != null &&
        _matchesAnyEtag(ifNoneMatch: ifNoneMatch, etag: etag)) {
      return Response.notModified(
        headers: <String, String>{
          'etag': etag,
          'x-marketplace-purchase-id': purchaseId,
        },
      );
    }

    return _ok(
      request,
      data: payload,
      headers: <String, String>{
        'etag': etag,
        'x-marketplace-purchase-id': purchaseId,
      },
      extra: nextCursor == null
          ? null
          : <String, Object?>{'next_cursor': nextCursor},
    );
  }

  Future<Response> applyCoupon(Request request) async {
    final body = await _readBodyOrValidationError(request);
    if (body.response != null) {
      return body.response!;
    }
    final userId = _requireUserId(request);
    if (userId == null) {
      return _error(
        request,
        401,
        errorCode: 'UNAUTHORIZED',
        message: 'Bearer token required',
      );
    }
    final payload = body.payload!;
    final orgId = _resolveOrgId(payload: payload, userId: userId);
    final couponCode =
        (payload['coupon_code'] as String?)?.trim() ??
        (payload['couponCode'] as String?)?.trim() ??
        '';
    final offerId =
        (payload['offer_id'] as String?)?.trim() ??
        (payload['offerId'] as String?)?.trim() ??
        'offer_sedan_01';
    final seats =
        _toInt(payload['seats']) ?? _toInt(payload['seat_count']) ?? 1;
    try {
      final result = await _revenueService.applyCoupon(
        orgId: orgId,
        userId: userId,
        couponCode: couponCode,
        offerId: offerId,
        seats: seats,
      );
      return _ok(request, data: result);
    } on MarketplaceRevenueException catch (error) {
      return _error(
        request,
        error.statusCode,
        errorCode: error.code,
        message: error.message,
      );
    }
  }

  Future<Response> removeCoupon(Request request) async {
    final body = await _readBodyOrValidationError(request);
    if (body.response != null) {
      return body.response!;
    }
    final userId = _requireUserId(request);
    if (userId == null) {
      return _error(
        request,
        401,
        errorCode: 'UNAUTHORIZED',
        message: 'Bearer token required',
      );
    }
    final payload = body.payload!;
    final orgId = _resolveOrgId(payload: payload, userId: userId);
    final offerId =
        (payload['offer_id'] as String?)?.trim() ??
        (payload['offerId'] as String?)?.trim() ??
        'offer_sedan_01';
    final seats =
        _toInt(payload['seats']) ?? _toInt(payload['seat_count']) ?? 1;
    try {
      final result = await _revenueService.removeCoupon(
        orgId: orgId,
        userId: userId,
        offerId: offerId,
        seats: seats,
      );
      return _ok(request, data: result);
    } on MarketplaceRevenueException catch (error) {
      return _error(
        request,
        error.statusCode,
        errorCode: error.code,
        message: error.message,
      );
    }
  }

  Future<Response> applyReferral(Request request) async {
    final body = await _readBodyOrValidationError(request);
    if (body.response != null) {
      return body.response!;
    }
    final userId = _requireUserId(request);
    if (userId == null) {
      return _error(
        request,
        401,
        errorCode: 'UNAUTHORIZED',
        message: 'Bearer token required',
      );
    }
    final payload = body.payload!;
    final orgId = _resolveOrgId(payload: payload, userId: userId);
    final referralCode =
        (payload['referral_code'] as String?)?.trim() ??
        (payload['referralCode'] as String?)?.trim() ??
        '';
    final offerId =
        (payload['offer_id'] as String?)?.trim() ??
        (payload['offerId'] as String?)?.trim() ??
        'offer_sedan_01';
    final seats =
        _toInt(payload['seats']) ?? _toInt(payload['seat_count']) ?? 1;
    try {
      final result = await _revenueService.applyReferral(
        orgId: orgId,
        userId: userId,
        referralCode: referralCode,
        offerId: offerId,
        seats: seats,
      );
      return _ok(request, data: result);
    } on MarketplaceRevenueException catch (error) {
      return _error(
        request,
        error.statusCode,
        errorCode: error.code,
        message: error.message,
      );
    }
  }

  Future<Response> pricingPreview(Request request) async {
    final userId = _requireUserId(request);
    if (userId == null) {
      return _error(
        request,
        401,
        errorCode: 'UNAUTHORIZED',
        message: 'Bearer token required',
      );
    }
    final query = request.url.queryParameters;
    final orgId = (query['org_id'] ?? query['orgId'] ?? '').trim().isEmpty
        ? userId
        : (query['org_id'] ?? query['orgId'] ?? '').trim();
    final offerId = (query['offer_id'] ?? query['offerId'] ?? 'offer_sedan_01')
        .trim();
    final seats = _toInt(query['seats']) ?? 1;
    try {
      final preview = await _revenueService.pricingPreview(
        orgId: orgId,
        userId: userId,
        offerId: offerId,
        seats: seats,
      );
      return _ok(request, data: preview.toMap());
    } on MarketplaceRevenueException catch (error) {
      return _error(
        request,
        error.statusCode,
        errorCode: error.code,
        message: error.message,
      );
    }
  }

  Future<Response> getOrgCredits(Request request, String orgId) async {
    final userId = _requireUserId(request);
    if (userId == null) {
      return _error(
        request,
        401,
        errorCode: 'UNAUTHORIZED',
        message: 'Bearer token required',
      );
    }
    final data = await _revenueService.creditsBalance(orgId);
    return _ok(request, data: data);
  }

  Future<Response> getOrgCreditsLedger(Request request, String orgId) async {
    final userId = _requireUserId(request);
    if (userId == null) {
      return _error(
        request,
        401,
        errorCode: 'UNAUTHORIZED',
        message: 'Bearer token required',
      );
    }
    final data = await _revenueService.creditsLedger(orgId);
    return _ok(request, data: data);
  }

  Future<Response> getOrgInvoices(Request request, String orgId) async {
    final userId = _requireUserId(request);
    if (userId == null) {
      return _error(
        request,
        401,
        errorCode: 'UNAUTHORIZED',
        message: 'Bearer token required',
      );
    }
    final data = await _revenueService.listInvoices(orgId);
    return _ok(request, data: data);
  }

  Future<Response> getOrgInvoice(
    Request request,
    String orgId,
    String invoiceId,
  ) async {
    final userId = _requireUserId(request);
    if (userId == null) {
      return _error(
        request,
        401,
        errorCode: 'UNAUTHORIZED',
        message: 'Bearer token required',
      );
    }
    final invoices = await _revenueService.listInvoices(orgId);
    for (final invoice in invoices) {
      if ((invoice['invoice_id'] ?? '').toString() == invoiceId) {
        return _ok(request, data: invoice);
      }
    }
    return _error(
      request,
      404,
      errorCode: 'NOT_FOUND',
      message: 'Invoice not found',
    );
  }

  Future<Response> setOrgPaymentMethod(Request request, String orgId) async {
    final userId = _requireUserId(request);
    if (userId == null) {
      return _error(
        request,
        401,
        errorCode: 'UNAUTHORIZED',
        message: 'Bearer token required',
      );
    }
    final body = await _readBodyOrValidationError(request);
    if (body.response != null) {
      return body.response!;
    }
    final payload = body.payload!;
    return _ok(
      request,
      data: <String, Object?>{
        'org_id': orgId,
        'updated': true,
        'provider': (payload['provider'] ?? 'manual').toString(),
        'status': 'stubbed',
      },
    );
  }

  Future<Response> retryOrgInvoice(
    Request request,
    String orgId,
    String invoiceId,
  ) async {
    final userId = _requireUserId(request);
    if (userId == null) {
      return _error(
        request,
        401,
        errorCode: 'UNAUTHORIZED',
        message: 'Bearer token required',
      );
    }
    try {
      final result = await _revenueService.retryInvoice(
        orgId: orgId,
        invoiceId: invoiceId,
      );
      return _ok(request, data: result);
    } on MarketplaceRevenueException catch (error) {
      return _error(
        request,
        error.statusCode,
        errorCode: error.code,
        message: error.message,
      );
    }
  }

  Future<Response> listOrgUsage(Request request, String orgId) async {
    final userId = _requireUserId(request);
    if (userId == null) {
      return _error(
        request,
        401,
        errorCode: 'UNAUTHORIZED',
        message: 'Bearer token required',
      );
    }
    return _ok(
      request,
      data: <String, Object?>{
        'org_id': orgId,
        'since': request.url.queryParameters['since'],
        'events': const <Map<String, Object?>>[],
      },
    );
  }

  Future<Response> listOrgUsageRollups(Request request, String orgId) async {
    final userId = _requireUserId(request);
    if (userId == null) {
      return _error(
        request,
        401,
        errorCode: 'UNAUTHORIZED',
        message: 'Bearer token required',
      );
    }
    return _ok(
      request,
      data: <String, Object?>{
        'org_id': orgId,
        'from': request.url.queryParameters['from'],
        'to': request.url.queryParameters['to'],
        'rollups': const <Map<String, Object?>>[],
      },
    );
  }

  _BodyParseResult _validationErrorResult(Response response) {
    return _BodyParseResult(payload: null, response: response);
  }

  Future<_BodyParseResult> _readBodyOrValidationError(Request request) async {
    try {
      final payload = await readJsonBody(request);
      return _BodyParseResult(payload: payload, response: null);
    } on FormatException catch (error) {
      return _validationErrorResult(
        _error(
          request,
          400,
          errorCode: 'VALIDATION_ERROR',
          message: error.message,
        ),
      );
    }
  }

  void _recordPurchaseAccess({
    required String purchaseId,
    required String ownerUserId,
    required String orgId,
    required String idempotencyKey,
  }) {
    _ownerUserIdByPurchaseId[purchaseId] = ownerUserId;
    _orgIdByPurchaseId[purchaseId] = orgId;
    _purchaseIdByOrgAndIdempotency['$orgId::$idempotencyKey'] = purchaseId;
    _versionByPurchaseId.putIfAbsent(purchaseId, () => 1);
  }

  _PurchaseAccess? _resolvePurchaseAccess({
    required String purchaseId,
    required String actingUserId,
  }) {
    final ownerUserId = _ownerUserIdByPurchaseId[purchaseId];
    final orgId = _orgIdByPurchaseId[purchaseId];
    if (ownerUserId == null || orgId == null) {
      return _PurchaseAccess(ownerUserId: actingUserId, orgId: actingUserId);
    }
    return _PurchaseAccess(ownerUserId: ownerUserId, orgId: orgId);
  }

  Future<Response?> _authorizePurchaseMutation({
    required Request request,
    required _PurchaseAccess purchaseAccess,
    required String actingUserId,
    required Set<String> allowedOrgRoles,
  }) async {
    if (purchaseAccess.ownerUserId == actingUserId) {
      return null;
    }
    final orgRepository = _orgRepository;
    if (orgRepository == null) {
      return _error(
        request,
        403,
        errorCode: 'FORBIDDEN',
        message: 'You do not have permission for this organization',
      );
    }
    final membership = await requireOrgRole(
      request: request,
      orgRepository: orgRepository,
      orgId: purchaseAccess.orgId,
      userId: actingUserId,
      allowedRoles: allowedOrgRoles,
    );
    if (membership == null) {
      return forbiddenOrgRole(request);
    }
    return null;
  }

  Future<Response?> _validateAssignmentAssignees({
    required Request request,
    required _PurchaseAccess purchaseAccess,
    required List<Map<String, Object?>> assignments,
  }) async {
    if (purchaseAccess.orgId == purchaseAccess.ownerUserId) {
      return null;
    }
    final orgRepository = _orgRepository;
    if (orgRepository == null) {
      return null;
    }
    for (final assignment in assignments) {
      final assigneeUserId =
          (assignment['user_id'] as String?)?.trim() ??
          (assignment['userId'] as String?)?.trim() ??
          '';
      if (assigneeUserId.isEmpty) {
        continue;
      }
      final membership = await orgRepository.findMembership(
        orgId: purchaseAccess.orgId,
        userId: assigneeUserId,
      );
      final status = (membership?['status'] as String?)?.toLowerCase() ?? '';
      if (membership == null || status != 'active') {
        return _error(
          request,
          400,
          errorCode: 'INVALID_ASSIGNEE',
          message: 'Assignment assignee must be an active organization member',
        );
      }
    }
    return null;
  }

  Future<bool> _hasActiveOrgMembership({
    required String orgId,
    required String userId,
  }) async {
    final orgRepository = _orgRepository;
    if (orgRepository == null) {
      return false;
    }
    final membership = await orgRepository.findMembership(
      orgId: orgId,
      userId: userId,
    );
    final status = (membership?['status'] as String?)?.toLowerCase() ?? '';
    return status == 'active';
  }

  int _currentVersion(String purchaseId) {
    return _versionByPurchaseId[purchaseId] ?? 1;
  }

  int _bumpVersion(String purchaseId) {
    final next = _currentVersion(purchaseId) + 1;
    _versionByPurchaseId[purchaseId] = next;
    return next;
  }

  Future<Map<String, Object?>> _buildPurchasePayload({
    required MarketplacePurchaseRecord purchase,
    required String ownerUserId,
    required String orgId,
    required int version,
  }) async {
    final assignments = await _offerRepository.listAssignments(
      userId: ownerUserId,
      purchaseId: purchase.id,
    );
    final assignmentPayload = assignments
        .map(
          (assignment) => <String, Object?>{
            'seatIndex': assignment.seatIndex,
            'name': assignment.name.trim().isEmpty
                ? assignment.assigneeUserId
                : assignment.name,
            'email': assignment.email.trim().isEmpty
                ? assignment.assigneeUserId
                : assignment.email,
          },
        )
        .toList(growable: false);
    final normalizedAssignments = assignmentPayload.isEmpty
        ? <Map<String, Object?>>[
            <String, Object?>{
              'seatIndex': 1,
              'name': ownerUserId,
              'email': ownerUserId,
            },
          ]
        : assignmentPayload;
    return <String, Object?>{
      ..._purchasePayload(purchase),
      'org_id': orgId,
      'assignments': normalizedAssignments,
      'version': version,
    };
  }

  Future<Response?> _versionConflictResponse({
    required Request request,
    required String purchaseId,
    required _PurchaseAccess purchaseAccess,
  }) async {
    final ifMatchVersion = (request.headers['if-match-version'] ?? '').trim();
    if (ifMatchVersion.isEmpty) {
      return null;
    }
    final expectedVersion = int.tryParse(ifMatchVersion);
    if (expectedVersion == null) {
      return _error(
        request,
        400,
        errorCode: 'VALIDATION_ERROR',
        message: 'if-match-version must be a valid integer',
      );
    }
    final currentVersion = _currentVersion(purchaseId);
    if (expectedVersion == currentVersion) {
      return null;
    }
    final latestPurchase = await _offerRepository.findPurchaseById(
      userId: purchaseAccess.ownerUserId,
      purchaseId: purchaseId,
    );
    if (latestPurchase == null) {
      return _error(
        request,
        404,
        errorCode: 'NOT_FOUND',
        message: 'Purchase not found',
      );
    }
    final latestPayload = await _buildPurchasePayload(
      purchase: latestPurchase,
      ownerUserId: purchaseAccess.ownerUserId,
      orgId: purchaseAccess.orgId,
      version: currentVersion,
    );
    return _error(
      request,
      409,
      errorCode: 'VERSION_CONFLICT',
      message: 'if-match-version does not match current version',
      data: <String, Object?>{'latest': latestPayload},
    );
  }

  Response _error(
    Request request,
    int statusCode, {
    required String errorCode,
    required String message,
    Object? data,
    Map<String, String>? headers,
  }) {
    final payload = <String, Object?>{
      'ok': false,
      'trace_id': _resolveTraceId(request),
      'error_code': errorCode,
      'message': message,
    };
    if (data != null) {
      payload['data'] = data;
    }
    return jsonResponse(
      statusCode,
      payload,
      headers: <String, String>{...?headers, 'x-error-code': errorCode},
    );
  }

  Response _ok(
    Request request, {
    required Object? data,
    int statusCode = 200,
    Map<String, String>? headers,
    Map<String, Object?>? extra,
  }) {
    final payload = <String, Object?>{
      'ok': true,
      'trace_id': _resolveTraceId(request),
      'data': data,
      ...?extra,
    };
    return jsonResponse(statusCode, payload, headers: headers);
  }

  String _etagForPayload(Object? payload) {
    final body = jsonEncode(payload);
    final hash = sha256.convert(utf8.encode(body)).toString();
    return '"$hash"';
  }

  bool _matchesAnyEtag({required String ifNoneMatch, required String etag}) {
    final normalizedTarget = _normalizeEtag(etag);
    final tokens = ifNoneMatch.split(',');
    for (final token in tokens) {
      final normalized = _normalizeEtag(token);
      if (normalized == '*' || normalized == normalizedTarget) {
        return true;
      }
    }
    return false;
  }

  String _normalizeEtag(String value) {
    var normalized = value.trim();
    if (normalized.startsWith('W/')) {
      normalized = normalized.substring(2).trim();
    }
    if (normalized.startsWith('"') && normalized.endsWith('"')) {
      normalized = normalized.substring(1, normalized.length - 1);
    }
    return normalized;
  }

  String _resolveTraceId(Request request) {
    final traceFromContext = request.requestContext.traceId.trim();
    if (traceFromContext.isNotEmpty && traceFromContext != 'trace-unset') {
      return traceFromContext;
    }

    final traceFromHeader = (request.headers['x-trace-id'] ?? '').trim();
    if (traceFromHeader.isNotEmpty) {
      return traceFromHeader;
    }

    return _uuid.v4();
  }

  int? _toInt(Object? value) {
    if (value is int) {
      return value;
    }
    if (value is num) {
      return value.toInt();
    }
    if (value is String) {
      return int.tryParse(value.trim());
    }
    return null;
  }

  _PaginationOptions _parsePaginationOptions({
    required Request request,
    required int defaultLimit,
    required int maxLimit,
  }) {
    final limitRaw = (request.url.queryParameters['limit'] ?? '').trim();
    var limit = defaultLimit;
    if (limitRaw.isNotEmpty) {
      final parsedLimit = int.tryParse(limitRaw);
      if (parsedLimit == null || parsedLimit < 1) {
        return _PaginationOptions(
          limit: defaultLimit,
          offset: 0,
          errorResponse: _error(
            request,
            400,
            errorCode: 'VALIDATION_ERROR',
            message: 'limit must be a positive integer',
          ),
        );
      }
      limit = parsedLimit > maxLimit ? maxLimit : parsedLimit;
    }

    final cursorRaw = (request.url.queryParameters['cursor'] ?? '').trim();
    final offsetRaw = (request.url.queryParameters['offset'] ?? '').trim();
    var offset = 0;
    if (cursorRaw.isNotEmpty) {
      final decodedOffset = _decodeCursorOffset(cursorRaw);
      if (decodedOffset == null) {
        return _PaginationOptions(
          limit: limit,
          offset: 0,
          errorResponse: _error(
            request,
            400,
            errorCode: 'VALIDATION_ERROR',
            message: 'cursor must be a valid pagination cursor',
          ),
        );
      }
      offset = decodedOffset;
    } else if (offsetRaw.isNotEmpty) {
      final parsedOffset = int.tryParse(offsetRaw);
      if (parsedOffset == null || parsedOffset < 0) {
        return _PaginationOptions(
          limit: limit,
          offset: 0,
          errorResponse: _error(
            request,
            400,
            errorCode: 'VALIDATION_ERROR',
            message: 'offset must be a non-negative integer',
          ),
        );
      }
      offset = parsedOffset;
    }

    return _PaginationOptions(
      limit: limit,
      offset: offset,
      errorResponse: null,
    );
  }

  int? _decodeCursorOffset(String cursor) {
    try {
      final normalized = _normalizeCursorBase64(cursor);
      final decoded = utf8.decode(base64Url.decode(normalized)).trim();
      final offset = int.tryParse(decoded);
      if (offset == null || offset < 0) {
        return null;
      }
      return offset;
    } catch (_) {
      return null;
    }
  }

  String _encodeCursor(int offset) {
    final encoded = base64UrlEncode(utf8.encode(offset.toString()));
    return encoded.replaceAll('=', '');
  }

  String _normalizeCursorBase64(String rawCursor) {
    final cursor = rawCursor.trim();
    final remainder = cursor.length % 4;
    if (remainder == 0) {
      return cursor;
    }
    final padding = List<String>.filled(4 - remainder, '=').join();
    return '$cursor$padding';
  }

  int _timestampSortValue(Object? rawTimestamp) {
    if (rawTimestamp is String) {
      final parsed = DateTime.tryParse(rawTimestamp)?.toUtc();
      if (parsed != null) {
        return parsed.microsecondsSinceEpoch;
      }
    }
    return 0;
  }

  String? _requireUserId(Request request) {
    final userId = request.requestContext.userId?.trim() ?? '';
    if (userId.isEmpty) {
      return null;
    }
    return userId;
  }

  String _resolveOrgId({
    required Map<String, Object?> payload,
    required String userId,
  }) {
    final orgId =
        (payload['org_id'] as String?)?.trim() ??
        (payload['orgId'] as String?)?.trim() ??
        '';
    if (orgId.isEmpty) {
      return userId;
    }
    return orgId;
  }

  Map<String, Object?> _purchasePayload(MarketplacePurchaseRecord purchase) {
    return <String, Object?>{
      'purchaseId': purchase.id,
      'offerId': purchase.offerId,
      'seatCount': purchase.seatCount,
      'status': purchase.status,
      'createdAt': purchase.createdAt.toUtc().toIso8601String(),
      'totalAmount': purchase.totalAmountMinor,
      'currency': purchase.currency,
      'offerTitle': purchase.offerTitle,
    };
  }

  Map<String, Object?> _timelineEventPayload({
    required MarketplaceTimelineEventRecord event,
    String? purchaseId,
  }) {
    return <String, Object?>{
      if (purchaseId != null) 'purchase_id': purchaseId,
      'type': _timelineEventTypeLabel(event.eventType),
      'title': _timelineEventTitle(event.eventType),
      'description': _timelineEventDescription(
        eventType: event.eventType,
        eventData: event.eventData,
      ),
      'timestamp': event.createdAt.toUtc().toIso8601String(),
      'status': _timelineStatus(event.eventType),
      'eventData': event.eventData,
    };
  }

  String _timelineEventTypeLabel(String eventType) {
    if (eventType.trim().isEmpty) {
      return 'UNKNOWN';
    }
    return eventType.trim().toUpperCase();
  }

  String _timelineEventTitle(String eventType) {
    switch (eventType.trim().toLowerCase()) {
      case 'purchase_created':
        return 'Purchase created';
      case 'seat_added':
        return 'Seat added';
      case 'seat_removed':
        return 'Seat removed';
      case 'seats_updated':
        return 'Seats updated';
      case 'assignment_updated':
        return 'Assignments updated';
      case 'plan_changed':
        return 'Plan changed';
      case 'payment_succeeded':
        return 'Payment succeeded';
      case 'payment_failed':
        return 'Payment failed';
      case 'webhook_received':
        return 'Webhook received';
      default:
        return eventType.replaceAll('_', ' ');
    }
  }

  String _timelineStatus(String eventType) {
    switch (eventType.trim().toLowerCase()) {
      case 'payment_failed':
        return 'ERROR';
      case 'purchase_created':
        return 'PENDING';
      default:
        return 'SUCCESS';
    }
  }

  String _timelineEventDescription({
    required String eventType,
    required Map<String, Object?> eventData,
  }) {
    switch (eventType.trim().toLowerCase()) {
      case 'purchase_created':
        final seatCount = _toInt(eventData['seat_count']) ?? 0;
        return 'Purchase initialized for $seatCount seat(s).';
      case 'seat_added':
      case 'seat_removed':
      case 'seats_updated':
        final currentSeatCount = _toInt(eventData['seat_count']) ?? 0;
        final delta = _toInt(eventData['delta']) ?? 0;
        return 'Seat count updated to $currentSeatCount (delta $delta).';
      case 'assignment_updated':
        final assignments = _toInt(eventData['assignment_count']) ?? 0;
        return '$assignments assignment(s) updated.';
      case 'plan_changed':
        final oldOffer = (eventData['old_offer_id'] ?? '').toString();
        final newOffer = (eventData['new_offer_id'] ?? '').toString();
        return 'Plan changed from $oldOffer to $newOffer.';
      case 'payment_succeeded':
        return 'Payment completed successfully.';
      case 'payment_failed':
        return 'Payment failed.';
      default:
        return eventData.isEmpty
            ? 'No additional details.'
            : eventData.toString();
    }
  }
}

class _BodyParseResult {
  const _BodyParseResult({required this.payload, required this.response});

  final Map<String, Object?>? payload;
  final Response? response;
}

class _PaginationOptions {
  const _PaginationOptions({
    required this.limit,
    required this.offset,
    required this.errorResponse,
  });

  final int limit;
  final int offset;
  final Response? errorResponse;
}

class _PurchaseAccess {
  const _PurchaseAccess({required this.ownerUserId, required this.orgId});

  final String ownerUserId;
  final String orgId;
}
