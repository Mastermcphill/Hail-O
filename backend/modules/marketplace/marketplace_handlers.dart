import 'package:shelf/shelf.dart';
import 'package:uuid/uuid.dart';

import '../../infra/request_context.dart';
import '../../server/http_utils.dart';
import 'marketplace_offer_repository.dart';

class MarketplaceHandlers {
  MarketplaceHandlers({
    required MarketplaceOfferRepository offerRepository,
    Uuid? uuid,
  }) : _offerRepository = offerRepository,
       _uuid = uuid ?? const Uuid();

  final MarketplaceOfferRepository _offerRepository;
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
      final purchase = await _offerRepository.createOrGetPurchase(
        userId: userId,
        offerId: offerId,
        seatCount: seatCount,
        idempotencyKey: idempotencyKey,
        provider: 'manual',
      );
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

    return _ok(
      request,
      data: <String, Object?>{
        ..._purchasePayload(purchase),
        'assignments': const <Map<String, Object?>>[],
      },
      headers: <String, String>{'x-marketplace-purchase-id': purchase.id},
    );
  }

  Response updateSeats(Request request, String purchaseId) {
    return _notImplemented(
      request,
      message: 'Marketplace seat updates are not implemented yet.',
    );
  }

  Response updateAssignments(Request request, String purchaseId) {
    return _notImplemented(
      request,
      message: 'Marketplace assignment updates are not implemented yet.',
    );
  }

  Response changePlan(Request request, String purchaseId) {
    return _notImplemented(
      request,
      message: 'Marketplace plan change is not implemented yet.',
    );
  }

  Response getTimeline(Request request, String purchaseId) {
    return _notImplemented(
      request,
      message: 'Marketplace timeline endpoint is not implemented yet.',
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

  Response _notImplemented(
    Request request, {
    required String message,
    Map<String, String>? headers,
  }) {
    return _error(
      request,
      501,
      errorCode: 'NOT_IMPLEMENTED',
      message: message,
      headers: headers,
    );
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
}

class _BodyParseResult {
  const _BodyParseResult({required this.payload, required this.response});

  final Map<String, Object?>? payload;
  final Response? response;
}
