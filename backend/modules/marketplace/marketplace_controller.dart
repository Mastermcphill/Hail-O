import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:shelf/shelf.dart';
import 'package:shelf_router/shelf_router.dart';

import '../../infra/request_context.dart';
import '../../infra/request_metrics.dart';
import '../../server/http_utils.dart';
import 'marketplace_envelope.dart';
import 'marketplace_entitlement_service.dart';
import 'marketplace_repository.dart';
import 'marketplace_timeline_service.dart';
import 'org_rbac.dart';
import 'org_repository.dart';
import 'payment_service.dart';

class MarketplaceController {
  MarketplaceController({
    required MarketplaceRepository marketplaceRepository,
    required OrgRepository orgRepository,
    required MarketplaceTimelineService timelineService,
    required MarketplaceEntitlementService entitlementService,
    required PaymentService paymentService,
    required RequestMetrics requestMetrics,
    void Function(String line)? logSink,
  }) : _marketplaceRepository = marketplaceRepository,
       _orgRepository = orgRepository,
       _timelineService = timelineService,
       _entitlementService = entitlementService,
       _paymentService = paymentService,
       _requestMetrics = requestMetrics,
       _logSink = logSink ?? print;

  final MarketplaceRepository _marketplaceRepository;
  final OrgRepository _orgRepository;
  final MarketplaceTimelineService _timelineService;
  final MarketplaceEntitlementService _entitlementService;
  final PaymentService _paymentService;
  final RequestMetrics _requestMetrics;
  final void Function(String line) _logSink;

  Router get router {
    final router = Router();
    router.get('/offers', _listOffers);
    router.get('/offers/<offerId>/paywall', _getPaywallCopy);
    router.post('/purchases', _createPurchase);
    router.get('/purchases/restore', _restorePurchase);
    router.get('/purchases/<purchaseId>', _getPurchase);
    router.patch('/purchases/<purchaseId>/seats', _updateSeats);
    router.patch('/purchases/<purchaseId>/assignments', _updateAssignments);
    router.post('/purchases/<purchaseId>/change-plan', _changePlan);
    router.get('/purchases/<purchaseId>/timeline', _timeline);
    return router;
  }

  Future<Response> _listOffers(Request request) {
    return _withObservability(
      request,
      route: '/marketplace/offers',
      action: () async {
        final offers = await _marketplaceRepository.listOffers();
        final data = offers.map(_offerToApi).toList(growable: false);
        final latestUpdatedAt = _latestUtcFromRows(offers, key: 'updated_at');
        final etag = _etagForValues(<Object?>[
          'offers',
          data.length,
          latestUpdatedAt?.millisecondsSinceEpoch,
        ]);
        final cacheHeaders = _cacheHeaders(
          etag: etag,
          lastModifiedUtc: latestUpdatedAt,
        );
        final notModified = _notModifiedResponse(
          request,
          etag: etag,
          lastModifiedUtc: latestUpdatedAt,
          headers: cacheHeaders,
        );
        if (notModified != null) {
          return notModified;
        }
        return marketplaceOk(request, data: data, headers: cacheHeaders);
      },
    );
  }

  Future<Response> _getPaywallCopy(Request request, String offerId) {
    return _withObservability(
      request,
      route: '/marketplace/offers/:offerId/paywall',
      action: () async {
        final offer = await _marketplaceRepository.findOfferById(offerId);
        if (offer == null) {
          return marketplaceError(
            request,
            statusCode: 404,
            errorCode: 'NOT_FOUND',
            message: 'Offer not found',
          );
        }
        final title = (offer['title'] as String?) ?? 'Marketplace Plan';
        final description = (offer['description'] as String?) ?? '';
        final features =
            (offer['features_json'] as List?)?.cast<Object?>() ??
            const <Object?>[];
        return marketplaceOk(
          request,
          data: <String, Object?>{
            'offerId': offer['id'],
            'headline': 'Unlock $title',
            'subhead': description.isEmpty
                ? 'Confirm your plan and continue to checkout.'
                : description,
            'bullets': features.map((item) => item.toString()).toList(),
            'legalText':
                'Billing is managed securely. Seat and plan changes are tracked for auditability.',
          },
        );
      },
    );
  }

  Future<Response> _createPurchase(Request request) {
    return _withObservability(
      request,
      route: '/marketplace/purchases',
      action: () async {
        final userId = _userIdOrEmpty(request);
        if (userId.isEmpty) {
          return marketplaceError(
            request,
            statusCode: 401,
            errorCode: 'UNAUTHORIZED',
            message: 'Missing user context',
          );
        }
        final body = await readJsonBody(request);
        final offerId =
            (body['offerId'] as String?)?.trim() ??
            (body['offer_id'] as String?)?.trim() ??
            '';
        final seatCount =
            (body['seatCount'] as num?)?.toInt() ??
            (body['seat_count'] as num?)?.toInt() ??
            1;
        final requestedOrgId =
            (body['orgId'] as String?)?.trim() ??
            (body['org_id'] as String?)?.trim() ??
            '';
        if (offerId.isEmpty) {
          return marketplaceError(
            request,
            statusCode: 400,
            errorCode: 'VALIDATION_ERROR',
            message: 'offerId is required',
          );
        }
        if (seatCount < 1 || seatCount > 50) {
          return marketplaceError(
            request,
            statusCode: 400,
            errorCode: 'VALIDATION_ERROR',
            message: 'seatCount must be between 1 and 50',
          );
        }
        final idempotencyKey = (request.requestContext.idempotencyKey ?? '')
            .trim();
        if (idempotencyKey.isEmpty) {
          return marketplaceError(
            request,
            statusCode: 400,
            errorCode: 'MISSING_IDEMPOTENCY_KEY',
            message: 'Idempotency-Key header is required',
          );
        }

        final assignmentsRaw = body['assignments'];
        final assignments = _normalizeAssignments(assignmentsRaw);
        String resolvedOrgId = requestedOrgId;
        String? requesterRole;
        String? orgName;
        if (resolvedOrgId.isEmpty) {
          final personalOrg = await _orgRepository.ensurePersonalOrg(
            userId: userId,
          );
          resolvedOrgId = (personalOrg['id'] as String?) ?? '';
          orgName = personalOrg['name']?.toString();
          requesterRole = 'owner';
        } else {
          final access = await requireBillingAccess(
            request: request,
            orgRepository: _orgRepository,
            orgId: resolvedOrgId,
            userId: userId,
          );
          if (access == null) {
            return forbiddenOrgRole(request);
          }
          requesterRole = access['role']?.toString();
          final org = await _orgRepository.findOrgById(resolvedOrgId);
          orgName = org?['name']?.toString();
        }
        final assignmentsForCreate = <Map<String, Object?>>[];
        final seenCreateAssignees = <String>{};
        for (var index = 0; index < assignments.length; index++) {
          final assignment = assignments[index];
          final assignee = resolvedOrgId.isEmpty
              ? _fallbackAssigneeValue(assignment)
              : await _resolveOrgAssignee(
                  orgId: resolvedOrgId,
                  assignment: assignment,
                );
          if (assignee == null || assignee.isEmpty) {
            return marketplaceError(
              request,
              statusCode: 400,
              errorCode: 'INVALID_ASSIGNEE',
              message: 'Seat assignee must be an active member of the org',
            );
          }
          if (seenCreateAssignees.contains(assignee)) {
            continue;
          }
          seenCreateAssignees.add(assignee);
          assignmentsForCreate.add(<String, Object?>{
            'seat_index':
                (assignment['seat_index'] as num?)?.toInt() ?? (index + 1),
            'assignee_user_id': assignee,
            'role':
                (assignment['role'] as String?)?.trim().toLowerCase() ??
                'member',
          });
        }
        if (assignmentsForCreate.length > seatCount) {
          return marketplaceError(
            request,
            statusCode: 400,
            errorCode: 'SEAT_LIMIT_EXCEEDED',
            message: 'Assignments exceed purchased seat count',
          );
        }
        final created = await _marketplaceRepository.createOrReusePurchase(
          userId: userId,
          offerId: offerId,
          seatCount: seatCount,
          idempotencyKey: idempotencyKey,
          provider: 'manual',
          orgId: resolvedOrgId.isEmpty ? null : resolvedOrgId,
          assignments: assignmentsForCreate,
        );
        final purchaseId = created['id'] as String;
        if (created['_replayed'] != true) {
          await _timelineService.appendEvent(
            purchaseId: purchaseId,
            type: 'purchase_created',
            data: <String, Object?>{
              'offer_id': offerId,
              'seat_count': seatCount,
            },
          );
        }

        final checkout = await _paymentService.createCheckoutOrIntent(
          purchase: created,
        );
        final purchase = await _marketplaceRepository.findPurchaseById(
          purchaseId,
        );
        if (purchase == null) {
          return marketplaceError(
            request,
            statusCode: 500,
            errorCode: 'INTERNAL_ERROR',
            message: 'Purchase could not be loaded',
          );
        }
        final assignmentsOut = await _marketplaceRepository.listAssignments(
          purchaseId,
        );
        return marketplaceOk(
          request,
          statusCode: created['_replayed'] == true ? 200 : 201,
          data: <String, Object?>{
            ..._purchaseToApi(
              purchase,
              assignmentsOut,
              requesterRole: requesterRole,
              orgName: orgName,
            ),
            'checkout': checkout,
            'replayed': created['_replayed'] == true,
          },
        );
      },
      purchaseIdResolver: (request) => _bodyPurchaseIdHint(request),
    );
  }

  Future<Response> _restorePurchase(Request request) {
    return _withObservability(
      request,
      route: '/marketplace/purchases/restore',
      action: () async {
        final userId = _userIdOrEmpty(request);
        if (userId.isEmpty) {
          return marketplaceError(
            request,
            statusCode: 401,
            errorCode: 'UNAUTHORIZED',
            message: 'Missing user context',
          );
        }
        final idempotencyKey =
            (request.requestedUri.queryParameters['idempotencyKey'] ?? '')
                .trim();
        if (idempotencyKey.isEmpty) {
          return marketplaceError(
            request,
            statusCode: 400,
            errorCode: 'VALIDATION_ERROR',
            message: 'idempotencyKey query parameter is required',
          );
        }
        final orgIds = await _orgRepository.listActiveOrgIdsForUser(userId);
        final purchase = await _marketplaceRepository
            .findPurchaseByIdempotencyAccessible(
          userId: userId,
          idempotencyKey: idempotencyKey,
          orgIds: orgIds,
        );
        if (purchase == null) {
          return marketplaceError(
            request,
            statusCode: 404,
            errorCode: 'NOT_FOUND',
            message: 'Purchase not found',
          );
        }
        final assignments = await _marketplaceRepository.listAssignments(
          purchase['id'] as String,
        );
        final orgId = (purchase['org_id'] as String?) ?? '';
        final org = orgId.isEmpty
            ? null
            : await _orgRepository.findOrgById(orgId);
        final membership = orgId.isEmpty
            ? null
            : await _orgRepository.findMembership(orgId: orgId, userId: userId);
        final requesterRole = orgId.isEmpty
            ? (purchase['user_id'] == userId ? 'owner' : null)
            : membership?['role']?.toString();
        return marketplaceOk(
          request,
          data: _purchaseToApi(
            purchase,
            assignments,
            requesterRole: requesterRole,
            orgName: org?['name']?.toString(),
          ),
        );
      },
    );
  }

  Future<Response> _getPurchase(Request request, String purchaseId) {
    return _withObservability(
      request,
      route: '/marketplace/purchases/:purchaseId',
      purchaseIdOverride: purchaseId,
      action: () async {
        final requesterUserId = _userIdOrEmpty(request);
        final purchase = await _marketplaceRepository.findPurchaseById(
          purchaseId,
        );
        if (purchase == null) {
          return marketplaceError(
            request,
            statusCode: 404,
            errorCode: 'NOT_FOUND',
            message: 'Purchase not found',
          );
        }
        if (!await _canAccessPurchase(request, purchase)) {
          return marketplaceError(
            request,
            statusCode: 403,
            errorCode: 'FORBIDDEN',
            message: 'Access denied',
          );
        }
        final assignments = await _marketplaceRepository.listAssignments(
          purchaseId,
        );
        final orgId = (purchase['org_id'] as String?)?.trim() ?? '';
        final org = orgId.isEmpty
            ? null
            : await _orgRepository.findOrgById(orgId);
        final membership = orgId.isEmpty
            ? null
            : await _orgRepository.findMembership(
                orgId: orgId,
                userId: requesterUserId,
              );
        final payload = _purchaseToApi(
          purchase,
          assignments,
          requesterRole: orgId.isEmpty
              ? (purchase['user_id'] == requesterUserId ? 'owner' : null)
              : membership?['role']?.toString(),
          orgName: org?['name']?.toString(),
        );
        final version = (payload['version'] as int?) ?? 1;
        final lastModifiedUtc = (purchase['updated_at'] as DateTime?)?.toUtc();
        final etag = _etagForValues(<Object?>['purchase', purchaseId, version]);
        final cacheHeaders = _cacheHeaders(
          etag: etag,
          lastModifiedUtc: lastModifiedUtc,
        );
        final notModified = _notModifiedResponse(
          request,
          etag: etag,
          lastModifiedUtc: lastModifiedUtc,
          headers: cacheHeaders,
        );
        if (notModified != null) {
          return notModified;
        }
        return marketplaceOk(request, data: payload, headers: cacheHeaders);
      },
    );
  }

  Future<Response> _updateSeats(Request request, String purchaseId) {
    return _withObservability(
      request,
      route: '/marketplace/purchases/:purchaseId/seats',
      purchaseIdOverride: purchaseId,
      action: () async {
        final requesterUserId = _userIdOrEmpty(request);
        final existing = await _marketplaceRepository.findPurchaseById(
          purchaseId,
        );
        if (existing == null) {
          return marketplaceError(
            request,
            statusCode: 404,
            errorCode: 'NOT_FOUND',
            message: 'Purchase not found',
          );
        }
        if (!await _canAccessPurchase(request, existing)) {
          return marketplaceError(
            request,
            statusCode: 403,
            errorCode: 'FORBIDDEN',
            message: 'Access denied',
          );
        }
        if (!await _canMutateBilling(request, existing)) {
          return forbiddenOrgRole(request);
        }
        final ifMatchVersion = _ifMatchVersion(request);
        if (ifMatchVersion == null) {
          return marketplaceError(
            request,
            statusCode: 400,
            errorCode: 'VALIDATION_ERROR',
            message: 'If-Match-Version header is required',
          );
        }
        final currentVersion = (existing['row_version'] as num?)?.toInt() ?? 1;
        if (ifMatchVersion != currentVersion) {
          final latestAssignments = await _marketplaceRepository
              .listAssignments(purchaseId);
          final orgId = (existing['org_id'] as String?)?.trim() ?? '';
          final org = orgId.isEmpty
              ? null
              : await _orgRepository.findOrgById(orgId);
          final membership = orgId.isEmpty
              ? null
              : await _orgRepository.findMembership(
                  orgId: orgId,
                  userId: requesterUserId,
                );
          return marketplaceError(
            request,
            statusCode: 409,
            errorCode: 'VERSION_CONFLICT',
            message: 'Resource version conflict. Refresh and retry.',
            data: <String, Object?>{
              'latest': _purchaseToApi(
                existing,
                latestAssignments,
                requesterRole: orgId.isEmpty
                    ? (existing['user_id'] == requesterUserId ? 'owner' : null)
                    : membership?['role']?.toString(),
                orgName: org?['name']?.toString(),
              ),
            },
          );
        }
        final body = await readJsonBody(request);
        final seatCount =
            (body['seatCount'] as num?)?.toInt() ??
            (body['seat_count'] as num?)?.toInt() ??
            (body['seats_total'] as num?)?.toInt() ??
            -1;
        if (seatCount < 1 || seatCount > 50) {
          return marketplaceError(
            request,
            statusCode: 400,
            errorCode: 'VALIDATION_ERROR',
            message: 'seatCount must be between 1 and 50',
          );
        }
        final previousSeats = (existing['seats_total'] as num?)?.toInt() ?? 1;
        final updated = await _marketplaceRepository.updatePurchaseSeats(
          purchaseId: purchaseId,
          seatCount: seatCount,
        );
        await _entitlementService.syncPurchaseEntitlementsFromMap(
          purchase: updated,
        );
        await _timelineService.appendEvent(
          purchaseId: purchaseId,
          type: 'seats_updated',
          data: <String, Object?>{
            'before': previousSeats,
            'after': seatCount,
            'delta': seatCount - previousSeats,
          },
        );
        final assignments = await _marketplaceRepository.listAssignments(
          purchaseId,
        );
        final updatedOrgId = (updated['org_id'] as String?)?.trim() ?? '';
        final updatedOrg = updatedOrgId.isEmpty
            ? null
            : await _orgRepository.findOrgById(updatedOrgId);
        final updatedMembership = updatedOrgId.isEmpty
            ? null
            : await _orgRepository.findMembership(
                orgId: updatedOrgId,
                userId: requesterUserId,
              );
        return marketplaceOk(
          request,
          data: _purchaseToApi(
            updated,
            assignments,
            requesterRole: updatedOrgId.isEmpty
                ? (updated['user_id'] == requesterUserId ? 'owner' : null)
                : updatedMembership?['role']?.toString(),
            orgName: updatedOrg?['name']?.toString(),
          ),
        );
      },
    );
  }

  Future<Response> _updateAssignments(Request request, String purchaseId) {
    return _withObservability(
      request,
      route: '/marketplace/purchases/:purchaseId/assignments',
      purchaseIdOverride: purchaseId,
      action: () async {
        final requesterUserId = _userIdOrEmpty(request);
        final existing = await _marketplaceRepository.findPurchaseById(
          purchaseId,
        );
        if (existing == null) {
          return marketplaceError(
            request,
            statusCode: 404,
            errorCode: 'NOT_FOUND',
            message: 'Purchase not found',
          );
        }
        if (!await _canAccessPurchase(request, existing)) {
          return marketplaceError(
            request,
            statusCode: 403,
            errorCode: 'FORBIDDEN',
            message: 'Access denied',
          );
        }
        if (!await _canMutateBilling(request, existing)) {
          return forbiddenOrgRole(request);
        }
        final ifMatchVersion = _ifMatchVersion(request);
        if (ifMatchVersion == null) {
          return marketplaceError(
            request,
            statusCode: 400,
            errorCode: 'VALIDATION_ERROR',
            message: 'If-Match-Version header is required',
          );
        }
        final currentVersion = (existing['row_version'] as num?)?.toInt() ?? 1;
        if (ifMatchVersion != currentVersion) {
          final latestAssignments = await _marketplaceRepository
              .listAssignments(purchaseId);
          final orgId = (existing['org_id'] as String?)?.trim() ?? '';
          final org = orgId.isEmpty
              ? null
              : await _orgRepository.findOrgById(orgId);
          final membership = orgId.isEmpty
              ? null
              : await _orgRepository.findMembership(
                  orgId: orgId,
                  userId: requesterUserId,
                );
          return marketplaceError(
            request,
            statusCode: 409,
            errorCode: 'VERSION_CONFLICT',
            message: 'Resource version conflict. Refresh and retry.',
            data: <String, Object?>{
              'latest': _purchaseToApi(
                existing,
                latestAssignments,
                requesterRole: orgId.isEmpty
                    ? (existing['user_id'] == requesterUserId ? 'owner' : null)
                    : membership?['role']?.toString(),
                orgName: org?['name']?.toString(),
              ),
            },
          );
        }
        final body = await readJsonBody(request);
        final rawAssignments = _normalizeAssignments(body['assignments']);
        final purchaseOrgId = (existing['org_id'] as String?)?.trim() ?? '';
        final normalizedAssignments = <Map<String, Object?>>[];
        final seenAssignees = <String>{};
        for (var index = 0; index < rawAssignments.length; index++) {
          final assignment = rawAssignments[index];
          final resolvedAssignee = purchaseOrgId.isEmpty
              ? _fallbackAssigneeValue(assignment)
              : await _resolveOrgAssignee(
                  orgId: purchaseOrgId,
                  assignment: assignment,
                );
          if (resolvedAssignee == null || resolvedAssignee.isEmpty) {
            return marketplaceError(
              request,
              statusCode: 400,
              errorCode: 'INVALID_ASSIGNEE',
              message: 'Seat assignee must be an active member of the org',
            );
          }
          if (seenAssignees.contains(resolvedAssignee)) {
            continue;
          }
          seenAssignees.add(resolvedAssignee);
          final seatIndex =
              (assignment['seat_index'] as num?)?.toInt() ?? (index + 1);
          normalizedAssignments.add(<String, Object?>{
            'seat_index': seatIndex <= 0 ? (index + 1) : seatIndex,
            'assignee_user_id': resolvedAssignee,
            'role':
                (assignment['role'] as String?)?.trim().toLowerCase() ??
                'member',
          });
        }
        final seatsTotal = (existing['seats_total'] as num?)?.toInt() ?? 1;
        if (normalizedAssignments.length > seatsTotal) {
          return marketplaceError(
            request,
            statusCode: 400,
            errorCode: 'SEAT_LIMIT_EXCEEDED',
            message: 'Assignments exceed purchased seat count',
          );
        }
        await _marketplaceRepository.replaceAssignments(
          purchaseId: purchaseId,
          assignments: normalizedAssignments,
          bumpPurchaseVersion: true,
        );
        await _timelineService.appendEvent(
          purchaseId: purchaseId,
          type: 'assignment_updated',
          data: <String, Object?>{'count': normalizedAssignments.length},
        );
        final purchase = await _marketplaceRepository.findPurchaseById(
          purchaseId,
        );
        if (purchase == null) {
          return marketplaceError(
            request,
            statusCode: 500,
            errorCode: 'INTERNAL_ERROR',
            message: 'Purchase could not be loaded',
          );
        }
        final freshAssignments = await _marketplaceRepository.listAssignments(
          purchaseId,
        );
        final org = purchaseOrgId.isEmpty
            ? null
            : await _orgRepository.findOrgById(purchaseOrgId);
        final membership = purchaseOrgId.isEmpty
            ? null
            : await _orgRepository.findMembership(
                orgId: purchaseOrgId,
                userId: requesterUserId,
              );
        return marketplaceOk(
          request,
          data: _purchaseToApi(
            purchase,
            freshAssignments,
            requesterRole: purchaseOrgId.isEmpty
                ? (purchase['user_id'] == requesterUserId ? 'owner' : null)
                : membership?['role']?.toString(),
            orgName: org?['name']?.toString(),
          ),
        );
      },
    );
  }

  Future<Response> _changePlan(Request request, String purchaseId) {
    return _withObservability(
      request,
      route: '/marketplace/purchases/:purchaseId/change-plan',
      purchaseIdOverride: purchaseId,
      action: () async {
        final requesterUserId = _userIdOrEmpty(request);
        final existing = await _marketplaceRepository.findPurchaseById(
          purchaseId,
        );
        if (existing == null) {
          return marketplaceError(
            request,
            statusCode: 404,
            errorCode: 'NOT_FOUND',
            message: 'Purchase not found',
          );
        }
        if (!await _canAccessPurchase(request, existing)) {
          return marketplaceError(
            request,
            statusCode: 403,
            errorCode: 'FORBIDDEN',
            message: 'Access denied',
          );
        }
        if (!await _canMutateBilling(request, existing)) {
          return forbiddenOrgRole(request);
        }
        final ifMatchVersion = _ifMatchVersion(request);
        if (ifMatchVersion == null) {
          return marketplaceError(
            request,
            statusCode: 400,
            errorCode: 'VALIDATION_ERROR',
            message: 'If-Match-Version header is required',
          );
        }
        final currentVersion = (existing['row_version'] as num?)?.toInt() ?? 1;
        if (ifMatchVersion != currentVersion) {
          final latestAssignments = await _marketplaceRepository
              .listAssignments(purchaseId);
          final orgId = (existing['org_id'] as String?)?.trim() ?? '';
          final org = orgId.isEmpty
              ? null
              : await _orgRepository.findOrgById(orgId);
          final membership = orgId.isEmpty
              ? null
              : await _orgRepository.findMembership(
                  orgId: orgId,
                  userId: requesterUserId,
                );
          return marketplaceError(
            request,
            statusCode: 409,
            errorCode: 'VERSION_CONFLICT',
            message: 'Resource version conflict. Refresh and retry.',
            data: <String, Object?>{
              'latest': _purchaseToApi(
                existing,
                latestAssignments,
                requesterRole: orgId.isEmpty
                    ? (existing['user_id'] == requesterUserId ? 'owner' : null)
                    : membership?['role']?.toString(),
                orgName: org?['name']?.toString(),
              ),
            },
          );
        }
        final body = await readJsonBody(request);
        final newOfferId =
            (body['offerId'] as String?)?.trim() ??
            (body['offer_id'] as String?)?.trim() ??
            '';
        if (newOfferId.isEmpty) {
          return marketplaceError(
            request,
            statusCode: 400,
            errorCode: 'VALIDATION_ERROR',
            message: 'offerId is required',
          );
        }
        final previousOfferId = (existing['offer_id'] as String?) ?? '';
        final updated = await _marketplaceRepository.updatePurchasePlan(
          purchaseId: purchaseId,
          offerId: newOfferId,
        );
        await _entitlementService.syncPurchaseEntitlementsFromMap(
          purchase: updated,
        );
        await _timelineService.appendEvent(
          purchaseId: purchaseId,
          type: 'plan_changed',
          data: <String, Object?>{
            'before_offer_id': previousOfferId,
            'after_offer_id': newOfferId,
          },
        );
        final assignments = await _marketplaceRepository.listAssignments(
          purchaseId,
        );
        final orgId = (updated['org_id'] as String?)?.trim() ?? '';
        final org = orgId.isEmpty
            ? null
            : await _orgRepository.findOrgById(orgId);
        final membership = orgId.isEmpty
            ? null
            : await _orgRepository.findMembership(
                orgId: orgId,
                userId: requesterUserId,
              );
        return marketplaceOk(
          request,
          data: _purchaseToApi(
            updated,
            assignments,
            requesterRole: orgId.isEmpty
                ? (updated['user_id'] == requesterUserId ? 'owner' : null)
                : membership?['role']?.toString(),
            orgName: org?['name']?.toString(),
          ),
        );
      },
    );
  }

  Future<Response> _timeline(Request request, String purchaseId) {
    return _withObservability(
      request,
      route: '/marketplace/purchases/:purchaseId/timeline',
      purchaseIdOverride: purchaseId,
      action: () async {
        final purchase = await _marketplaceRepository.findPurchaseById(
          purchaseId,
        );
        if (purchase == null) {
          return marketplaceError(
            request,
            statusCode: 404,
            errorCode: 'NOT_FOUND',
            message: 'Purchase not found',
          );
        }
        if (!await _canAccessPurchase(request, purchase)) {
          return marketplaceError(
            request,
            statusCode: 403,
            errorCode: 'FORBIDDEN',
            message: 'Access denied',
          );
        }
        final query = request.requestedUri.queryParameters;
        final sinceUtc = _parseSinceQuery(query['since']);
        final limit = _normalizeTimelineLimit(query['limit']);
        final events = await _timelineService.listEvents(
          purchaseId,
          limit: limit,
          sinceUtc: sinceUtc,
        );
        final eventData = events.map(_timelineToApi).toList(growable: false);
        final latestEventAtUtc = _latestUtcFromRows(events, key: 'created_at');
        final latestCursor = _latestIntFromRows(events, key: 'event_seq');
        final etag = _etagForValues(<Object?>[
          'timeline',
          purchaseId,
          sinceUtc?.millisecondsSinceEpoch,
          latestCursor,
          eventData.length,
        ]);
        final cacheHeaders = _cacheHeaders(
          etag: etag,
          lastModifiedUtc:
              latestEventAtUtc ??
              (purchase['updated_at'] as DateTime?)?.toUtc(),
        );
        final notModified = _notModifiedResponse(
          request,
          etag: etag,
          lastModifiedUtc:
              latestEventAtUtc ??
              (purchase['updated_at'] as DateTime?)?.toUtc(),
          headers: cacheHeaders,
        );
        if (notModified != null) {
          return notModified;
        }
        return marketplaceOk(
          request,
          data: <String, Object?>{
            'events': eventData,
            'latest_event_at': latestEventAtUtc?.toIso8601String(),
            'cursor': latestCursor?.toString(),
          },
          headers: cacheHeaders,
        );
      },
    );
  }

  Future<Response> _withObservability(
    Request request, {
    required String route,
    required Future<Response> Function() action,
    String? purchaseIdOverride,
    String? Function(Request request)? purchaseIdResolver,
  }) async {
    final watch = Stopwatch()..start();
    var statusCode = 500;
    var errorCode = '';
    String? purchaseId = purchaseIdOverride;
    try {
      purchaseId ??= purchaseIdResolver?.call(request);
      final response = await action();
      statusCode = response.statusCode;
      errorCode = response.headers['x-error-code'] ?? '';
      return response;
    } on FormatException catch (error) {
      statusCode = 400;
      errorCode = 'INVALID_JSON';
      return marketplaceError(
        request,
        statusCode: 400,
        errorCode: 'INVALID_JSON',
        message: error.message,
      );
    } on StateError catch (error) {
      statusCode = 400;
      final message = error.message.toString();
      errorCode =
          message == 'offer_not_found' || message == 'purchase_not_found'
          ? 'NOT_FOUND'
          : 'VALIDATION_ERROR';
      return marketplaceError(
        request,
        statusCode: errorCode == 'NOT_FOUND' ? 404 : 400,
        errorCode: errorCode,
        message: message,
      );
    } catch (_) {
      statusCode = 500;
      errorCode = 'INTERNAL_ERROR';
      return marketplaceError(
        request,
        statusCode: 500,
        errorCode: 'INTERNAL_ERROR',
        message: 'Unexpected server error',
      );
    } finally {
      watch.stop();
      _requestMetrics.recordMarketplaceRequest(
        route: route,
        method: request.method,
        statusCode: statusCode,
        latencyMs: watch.elapsedMilliseconds,
      );
      _logSink(
        jsonEncode(<String, Object?>{
          'trace_id': request.requestContext.traceId,
          'route': route,
          'method': request.method,
          'user_id': request.requestContext.userId,
          'status_code': statusCode,
          'latency_ms': watch.elapsedMilliseconds,
          if ((request.requestContext.idempotencyKey ?? '').isNotEmpty)
            'idempotency_key': _shortHash(
              request.requestContext.idempotencyKey!,
            ),
          if (purchaseId != null && purchaseId.isNotEmpty)
            'purchase_id': purchaseId,
          if (errorCode.isNotEmpty) 'error_code': errorCode,
        }),
      );
    }
  }

  String _userIdOrEmpty(Request request) {
    return (request.requestContext.userId ?? '').trim();
  }

  Future<bool> _canAccessPurchase(
    Request request,
    Map<String, Object?> purchase,
  ) async {
    final role = (request.requestContext.role ?? '').trim().toLowerCase();
    if (role == 'admin') {
      return true;
    }
    final userId = _userIdOrEmpty(request);
    final orgId = (purchase['org_id'] as String?)?.trim() ?? '';
    if (orgId.isNotEmpty) {
      final membership = await _orgRepository.findMembership(
        orgId: orgId,
        userId: userId,
      );
      if (membership == null) {
        return false;
      }
      return (membership['status'] as String?)?.toLowerCase() == 'active';
    }
    final ownerId = (purchase['user_id'] as String?) ?? '';
    return userId.isNotEmpty && ownerId == userId;
  }

  Future<bool> _canMutateBilling(
    Request request,
    Map<String, Object?> purchase,
  ) async {
    final role = (request.requestContext.role ?? '').trim().toLowerCase();
    if (role == 'admin') {
      return true;
    }
    final userId = _userIdOrEmpty(request);
    final orgId = (purchase['org_id'] as String?)?.trim() ?? '';
    if (orgId.isEmpty) {
      final ownerId = (purchase['user_id'] as String?) ?? '';
      return userId.isNotEmpty && ownerId == userId;
    }
    final membership = await requireBillingAccess(
      request: request,
      orgRepository: _orgRepository,
      orgId: orgId,
      userId: userId,
    );
    return membership != null;
  }

  List<Map<String, Object?>> _normalizeAssignments(Object? raw) {
    if (raw is! List) {
      return <Map<String, Object?>>[];
    }
    return raw
        .whereType<Map>()
        .map((assignment) {
          final map = assignment.map(
            (key, value) => MapEntry(key.toString(), value as Object?),
          );
          return Map<String, Object?>.from(map);
        })
        .toList(growable: false);
  }

  String _fallbackAssigneeValue(Map<String, Object?> assignment) {
    final direct =
        (assignment['assignee_user_id'] as String?)?.trim() ??
        (assignment['user_id'] as String?)?.trim() ??
        '';
    if (direct.isNotEmpty) {
      return direct;
    }
    final email = (assignment['email'] as String?)?.trim() ?? '';
    if (email.isNotEmpty) {
      return email;
    }
    return (assignment['name'] as String?)?.trim() ?? '';
  }

  Future<String?> _resolveOrgAssignee({
    required String orgId,
    required Map<String, Object?> assignment,
  }) async {
    final directUserId =
        (assignment['user_id'] as String?)?.trim() ??
        (assignment['assignee_user_id'] as String?)?.trim() ??
        '';
    if (directUserId.isNotEmpty) {
      final membership = await _orgRepository.findMembership(
        orgId: orgId,
        userId: directUserId,
      );
      if (membership != null &&
          ((membership['status'] as String?)?.toLowerCase() == 'active')) {
        return directUserId;
      }
    }

    final email =
        (assignment['email'] as String?)?.trim().toLowerCase() ??
        (assignment['name'] as String?)?.trim().toLowerCase() ??
        '';
    if (email.isEmpty) {
      return null;
    }
    final memberFromEmail = await _orgRepository.findMembership(
      orgId: orgId,
      userId: email,
    );
    if (memberFromEmail != null &&
        ((memberFromEmail['status'] as String?)?.toLowerCase() == 'active')) {
      return email;
    }
    final invite = await _orgRepository.findInviteByOrgAndEmail(
      orgId: orgId,
      email: email,
    );
    final acceptedUserId =
        (invite?['accepted_by_user_id'] as String?)?.trim() ?? '';
    if (acceptedUserId.isEmpty) {
      return null;
    }
    final acceptedMembership = await _orgRepository.findMembership(
      orgId: orgId,
      userId: acceptedUserId,
    );
    if (acceptedMembership == null ||
        ((acceptedMembership['status'] as String?)?.toLowerCase() !=
            'active')) {
      return null;
    }
    return acceptedUserId;
  }

  Map<String, Object?> _offerToApi(Map<String, Object?> offer) {
    final features =
        (offer['features_json'] as List?)?.cast<Object?>() ?? const <Object?>[];
    return <String, Object?>{
      'id': offer['id'],
      'title': offer['title'],
      'subtitle': offer['description'],
      'price': offer['price_minor'],
      'currency': offer['currency'],
      'interval': offer['interval'],
      'perks': features.map((item) => item.toString()).toList(growable: false),
    };
  }

  Map<String, Object?> _purchaseToApi(
    Map<String, Object?> purchase,
    List<Map<String, Object?>> assignments,
    {
    String? requesterRole,
    String? orgName,
  }) {
    final purchaseVersion = (purchase['row_version'] as num?)?.toInt() ?? 1;
    final assignmentsVersion = _assignmentVersion(assignments, purchaseVersion);
    return <String, Object?>{
      'purchaseId': purchase['id'],
      'offerId': purchase['offer_id'],
      'org_id': purchase['org_id'],
      'org_name': orgName,
      'requester_role': requesterRole,
      'seatCount': purchase['seats_total'],
      'status': purchase['status'],
      'createdAt': (purchase['created_at'] as DateTime?)?.toIso8601String(),
      'totalAmount': purchase['price_minor'],
      'currency': purchase['currency'],
      'assignments': assignments
          .map(
            (assignment) => <String, Object?>{
              'seatIndex': assignment['seat_index'],
              'name': assignment['assignee_user_id'],
              'email': assignment['assignee_user_id'],
            },
          )
          .toList(growable: false),
      'version': purchaseVersion,
      'assignments_version': assignmentsVersion,
      'provider': purchase['provider'],
      'providerRef': purchase['provider_payment_intent_id'],
    };
  }

  Map<String, Object?> _timelineToApi(Map<String, Object?> event) {
    final eventType = ((event['event_type'] as String?) ?? 'webhook_received')
        .toUpperCase();
    final payload = event['event_data'] is Map<String, Object?>
        ? (event['event_data'] as Map<String, Object?>)
        : const <String, Object?>{};
    return <String, Object?>{
      'type': eventType,
      'title': eventType.replaceAll('_', ' '),
      'description': payload.isEmpty ? 'Marketplace event' : payload.toString(),
      'timestamp': (event['created_at'] as DateTime?)?.toIso8601String(),
      'cursor': event['event_seq']?.toString(),
      'status': _statusFromEventType(eventType),
    };
  }

  String _statusFromEventType(String eventType) {
    if (eventType.contains('FAILED')) {
      return 'error';
    }
    if (eventType.contains('REFUND') || eventType.contains('CHARGEBACK')) {
      return 'warning';
    }
    return 'ok';
  }

  Map<String, String> _cacheHeaders({
    required String etag,
    DateTime? lastModifiedUtc,
  }) {
    final headers = <String, String>{'etag': '"$etag"'};
    if (lastModifiedUtc != null) {
      headers[HttpHeaders.lastModifiedHeader] = HttpDate.format(
        lastModifiedUtc.toUtc(),
      );
    }
    return headers;
  }

  Response? _notModifiedResponse(
    Request request, {
    required String etag,
    DateTime? lastModifiedUtc,
    required Map<String, String> headers,
  }) {
    final ifNoneMatch = request.headers[HttpHeaders.ifNoneMatchHeader];
    if (ifNoneMatch != null &&
        _matchesAnyEtag(ifNoneMatch: ifNoneMatch, etag: etag)) {
      return Response.notModified(headers: headers);
    }
    final ifModifiedSince = request.headers[HttpHeaders.ifModifiedSinceHeader];
    if (ifModifiedSince != null && lastModifiedUtc != null) {
      try {
        final sinceUtc = HttpDate.parse(ifModifiedSince).toUtc();
        if (!lastModifiedUtc.toUtc().isAfter(sinceUtc)) {
          return Response.notModified(headers: headers);
        }
      } catch (_) {
        // ignore malformed conditional header
      }
    }
    return null;
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

  String _etagForValues(List<Object?> values) {
    final raw = values.map((value) => value?.toString() ?? '').join('|');
    return sha1.convert(utf8.encode(raw)).toString();
  }

  DateTime? _latestUtcFromRows(
    List<Map<String, Object?>> rows, {
    required String key,
  }) {
    DateTime? latest;
    for (final row in rows) {
      final value = row[key];
      if (value is! DateTime) {
        continue;
      }
      final candidate = value.toUtc();
      if (latest == null || candidate.isAfter(latest)) {
        latest = candidate;
      }
    }
    return latest;
  }

  int? _latestIntFromRows(
    List<Map<String, Object?>> rows, {
    required String key,
  }) {
    int? latest;
    for (final row in rows) {
      final value = (row[key] as num?)?.toInt();
      if (value == null) {
        continue;
      }
      if (latest == null || value > latest) {
        latest = value;
      }
    }
    return latest;
  }

  int _assignmentVersion(
    List<Map<String, Object?>> assignments,
    int purchaseVersion,
  ) {
    var version = 0;
    for (final assignment in assignments) {
      final current = (assignment['row_version'] as num?)?.toInt() ?? 0;
      if (current > version) {
        version = current;
      }
    }
    if (version > 0) {
      return version;
    }
    return purchaseVersion;
  }

  int? _ifMatchVersion(Request request) {
    final raw = (request.headers['if-match-version'] ?? '').trim();
    if (raw.isEmpty) {
      return null;
    }
    return int.tryParse(raw);
  }

  DateTime? _parseSinceQuery(String? raw) {
    final value = (raw ?? '').trim();
    if (value.isEmpty) {
      return null;
    }
    return DateTime.tryParse(value)?.toUtc();
  }

  int _normalizeTimelineLimit(String? raw) {
    final parsed = int.tryParse((raw ?? '').trim());
    if (parsed == null || parsed <= 0) {
      return 100;
    }
    if (parsed > 200) {
      return 200;
    }
    return parsed;
  }

  String _shortHash(String value) {
    if (value.length <= 12) {
      return value;
    }
    return value.substring(0, 12);
  }

  String? _bodyPurchaseIdHint(Request request) {
    final path = request.url.path;
    if (path.contains('/purchases/')) {
      final segments = path.split('/');
      final index = segments.indexOf('purchases');
      if (index >= 0 && index + 1 < segments.length) {
        return segments[index + 1];
      }
    }
    return null;
  }
}
