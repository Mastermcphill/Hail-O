import 'package:shelf/shelf.dart';
import 'package:uuid/uuid.dart';

import '../../infra/request_context.dart';
import '../../server/http_utils.dart';
import '../payments/payment_service.dart';
import 'marketplace_offer_repository.dart';

class MarketplaceHandlers {
  MarketplaceHandlers({
    required MarketplaceOfferRepository offerRepository,
    PaymentService? paymentService,
    Uuid? uuid,
  }) : _offerRepository = offerRepository,
       _paymentService = paymentService,
       _uuid = uuid ?? const Uuid();

  final MarketplaceOfferRepository _offerRepository;
  final PaymentService? _paymentService;
  final Uuid _uuid;

  Future<Response> listOffers(Request request) async {
    final offers = await _offerRepository.listActiveOffers();
    final data = offers
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
    return _ok(request, data: data);
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
      return _ok(
        request,
        data: _purchasePayload(purchase),
        headers: <String, String>{
          'x-idempotency-key': idempotencyKey,
          'x-marketplace-purchase-id': purchase.id,
        },
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
    final userId = _requireUserId(request);
    if (userId == null) {
      return _error(
        request,
        401,
        errorCode: 'UNAUTHORIZED',
        message: 'Bearer token required',
      );
    }

    final idempotencyKey = (request.url.queryParameters['idempotencyKey'] ?? '')
        .trim();
    if (idempotencyKey.isEmpty) {
      return _error(
        request,
        400,
        errorCode: 'VALIDATION_ERROR',
        message: 'idempotencyKey query parameter is required',
      );
    }

    final purchase = await _offerRepository.findPurchaseByIdempotencyKey(
      userId: userId,
      idempotencyKey: idempotencyKey,
    );
    if (purchase == null) {
      return _error(
        request,
        404,
        errorCode: 'NOT_FOUND',
        message: 'Purchase not found for idempotency key',
      );
    }

    return _ok(
      request,
      data: _purchasePayload(purchase),
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

    final purchase = await _offerRepository.findPurchaseById(
      userId: userId,
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
    final assignments = await _offerRepository.listAssignments(
      userId: userId,
      purchaseId: purchaseId,
    );

    return _ok(
      request,
      data: <String, Object?>{
        ..._purchasePayload(purchase),
        'assignments': assignments
            .map(
              (assignment) => <String, Object?>{
                'seatIndex': assignment.seatIndex,
                'name': assignment.name,
                'email': assignment.email,
              },
            )
            .toList(growable: false),
      },
      headers: <String, String>{'x-marketplace-purchase-id': purchase.id},
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

    try {
      final purchase = await _offerRepository.updateSeatCount(
        userId: userId,
        purchaseId: purchaseId,
        seatCount: seatCount,
      );
      return _ok(
        request,
        data: _purchasePayload(purchase),
        headers: <String, String>{'x-marketplace-purchase-id': purchase.id},
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
    for (final item in rawAssignments) {
      if (item is! Map) {
        continue;
      }
      final map = Map<String, Object?>.from(
        item.map((key, value) => MapEntry(key.toString(), value)),
      );
      final seatIndex =
          _toInt(map['seatIndex']) ?? _toInt(map['seat_number']) ?? 0;
      assignments.add(
        MarketplaceSeatAssignmentInput(
          seatIndex: seatIndex,
          name: (map['name'] as String?)?.trim() ?? '',
          email: (map['email'] as String?)?.trim() ?? '',
        ),
      );
    }

    try {
      final purchase = await _offerRepository.replaceAssignments(
        userId: userId,
        purchaseId: purchaseId,
        assignments: assignments,
      );
      return _ok(
        request,
        data: _purchasePayload(purchase),
        headers: <String, String>{'x-marketplace-purchase-id': purchase.id},
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
        '';
    if (newOfferId.isEmpty) {
      return _error(
        request,
        400,
        errorCode: 'VALIDATION_ERROR',
        message: 'new_offer_id is required',
      );
    }

    try {
      final purchase = await _offerRepository.changePlan(
        userId: userId,
        purchaseId: purchaseId,
        newOfferId: newOfferId,
      );
      return _ok(
        request,
        data: _purchasePayload(purchase),
        headers: <String, String>{'x-marketplace-purchase-id': purchase.id},
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

    final limit = _toInt(request.url.queryParameters['limit']) ?? 100;
    final events = await _offerRepository.listTimelineEvents(
      userId: userId,
      purchaseId: purchaseId,
      limit: limit,
    );
    if (events.isEmpty) {
      final purchase = await _offerRepository.findPurchaseById(
        userId: userId,
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

    final timeline = events
        .map(
          (event) => <String, Object?>{
            'type': _timelineEventTypeLabel(event.eventType),
            'title': _timelineEventTitle(event.eventType),
            'description': _timelineEventDescription(
              eventType: event.eventType,
              eventData: event.eventData,
            ),
            'timestamp': event.createdAt.toUtc().toIso8601String(),
            'status': _timelineStatus(event.eventType),
            'eventData': event.eventData,
          },
        )
        .toList(growable: false);

    return _ok(
      request,
      data: timeline,
      headers: <String, String>{'x-marketplace-purchase-id': purchaseId},
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

  Response _error(
    Request request,
    int statusCode, {
    required String errorCode,
    required String message,
    Map<String, String>? headers,
  }) {
    return jsonResponse(
      statusCode,
      <String, Object?>{
        'ok': false,
        'trace_id': _resolveTraceId(request),
        'error_code': errorCode,
        'message': message,
      },
      headers: <String, String>{...?headers, 'x-error-code': errorCode},
    );
  }

  Response _ok(
    Request request, {
    required Object? data,
    int statusCode = 200,
    Map<String, String>? headers,
  }) {
    return jsonResponse(statusCode, <String, Object?>{
      'ok': true,
      'trace_id': _resolveTraceId(request),
      'data': data,
    }, headers: headers);
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

  String? _requireUserId(Request request) {
    final userId = request.requestContext.userId?.trim() ?? '';
    if (userId.isEmpty) {
      return null;
    }
    return userId;
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
