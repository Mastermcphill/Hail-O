import 'dart:convert';

import 'package:shelf/shelf.dart';
import 'package:shelf_router/shelf_router.dart';

import '../../infra/request_context.dart';
import '../../infra/request_metrics.dart';
import '../../server/http_utils.dart';
import 'marketplace_envelope.dart';
import 'marketplace_entitlement_service.dart';
import 'marketplace_repository.dart';
import 'marketplace_timeline_service.dart';
import 'payment_service.dart';

class MarketplaceController {
  MarketplaceController({
    required MarketplaceRepository marketplaceRepository,
    required MarketplaceTimelineService timelineService,
    required MarketplaceEntitlementService entitlementService,
    required PaymentService paymentService,
    required RequestMetrics requestMetrics,
    void Function(String line)? logSink,
  }) : _marketplaceRepository = marketplaceRepository,
       _timelineService = timelineService,
       _entitlementService = entitlementService,
       _paymentService = paymentService,
       _requestMetrics = requestMetrics,
       _logSink = logSink ?? print;

  final MarketplaceRepository _marketplaceRepository;
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
        return marketplaceOk(request, data: data);
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
        final created = await _marketplaceRepository.createOrReusePurchase(
          userId: userId,
          offerId: offerId,
          seatCount: seatCount,
          idempotencyKey: idempotencyKey,
          provider: 'manual',
          assignments: assignments,
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
            ..._purchaseToApi(purchase, assignmentsOut),
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
        final purchase = await _marketplaceRepository.findPurchaseByIdempotency(
          userId: userId,
          idempotencyKey: idempotencyKey,
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
        return marketplaceOk(
          request,
          data: _purchaseToApi(purchase, assignments),
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
        if (!_canAccessPurchase(request, purchase)) {
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
        return marketplaceOk(
          request,
          data: _purchaseToApi(purchase, assignments),
        );
      },
    );
  }

  Future<Response> _updateSeats(Request request, String purchaseId) {
    return _withObservability(
      request,
      route: '/marketplace/purchases/:purchaseId/seats',
      purchaseIdOverride: purchaseId,
      action: () async {
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
        if (!_canAccessPurchase(request, existing)) {
          return marketplaceError(
            request,
            statusCode: 403,
            errorCode: 'FORBIDDEN',
            message: 'Access denied',
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
        await _entitlementService.syncPurchaseEntitlements(updated);
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
        return marketplaceOk(
          request,
          data: _purchaseToApi(updated, assignments),
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
        if (!_canAccessPurchase(request, existing)) {
          return marketplaceError(
            request,
            statusCode: 403,
            errorCode: 'FORBIDDEN',
            message: 'Access denied',
          );
        }
        final body = await readJsonBody(request);
        final assignments = _normalizeAssignments(body['assignments']);
        await _marketplaceRepository.replaceAssignments(
          purchaseId: purchaseId,
          assignments: assignments,
        );
        await _timelineService.appendEvent(
          purchaseId: purchaseId,
          type: 'assignment_updated',
          data: <String, Object?>{'count': assignments.length},
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
        return marketplaceOk(
          request,
          data: _purchaseToApi(purchase, freshAssignments),
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
        if (!_canAccessPurchase(request, existing)) {
          return marketplaceError(
            request,
            statusCode: 403,
            errorCode: 'FORBIDDEN',
            message: 'Access denied',
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
        await _entitlementService.syncPurchaseEntitlements(updated);
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
        return marketplaceOk(
          request,
          data: _purchaseToApi(updated, assignments),
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
        if (!_canAccessPurchase(request, purchase)) {
          return marketplaceError(
            request,
            statusCode: 403,
            errorCode: 'FORBIDDEN',
            message: 'Access denied',
          );
        }
        final events = await _timelineService.listEvents(purchaseId);
        final data = events.map(_timelineToApi).toList(growable: false);
        return marketplaceOk(request, data: data);
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

  bool _canAccessPurchase(Request request, Map<String, Object?> purchase) {
    final role = (request.requestContext.role ?? '').trim().toLowerCase();
    if (role == 'admin') {
      return true;
    }
    final userId = _userIdOrEmpty(request);
    final ownerId = (purchase['user_id'] as String?) ?? '';
    return userId.isNotEmpty && ownerId == userId;
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
  ) {
    return <String, Object?>{
      'purchaseId': purchase['id'],
      'offerId': purchase['offer_id'],
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
