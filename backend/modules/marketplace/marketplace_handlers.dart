import 'package:shelf/shelf.dart';
import 'package:uuid/uuid.dart';

import '../../infra/request_context.dart';
import '../../server/http_utils.dart';

class MarketplaceHandlers {
  MarketplaceHandlers({Uuid? uuid}) : _uuid = uuid ?? const Uuid();

  final Uuid _uuid;

  Response listOffers(Request request) {
    return _notImplemented(
      request,
      message: 'Marketplace offers endpoint is not implemented yet.',
    );
  }

  Response getOfferPaywall(Request request, String offerId) {
    return _notImplemented(
      request,
      message: 'Marketplace paywall endpoint is not implemented yet.',
    );
  }

  Future<Response> createPurchase(Request request) async {
    final body = await _readBodyOrValidationError(request);
    if (body.response != null) {
      return body.response!;
    }

    final payload = body.payload!;
    final offerId = (payload['offerId'] as String?)?.trim() ?? '';
    final seatCount = _toInt(payload['seatCount']);
    final idempotencyKey = (request.headers['idempotency-key'] ?? '').trim();

    if (offerId.isEmpty || seatCount == null || seatCount < 1) {
      return _error(
        request,
        400,
        errorCode: 'VALIDATION_ERROR',
        message: 'offerId and seatCount>=1 are required',
      );
    }

    final responseHeaders = idempotencyKey.isNotEmpty
        ? <String, String>{'x-idempotency-key': idempotencyKey}
        : null;
    return _notImplemented(
      request,
      message: 'Marketplace purchase creation is not implemented yet.',
      headers: responseHeaders,
    );
  }

  Response restorePurchase(Request request) {
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

    return _notImplemented(
      request,
      message: 'Marketplace purchase restore is not implemented yet.',
    );
  }

  Response getPurchase(Request request, String purchaseId) {
    return _notImplemented(
      request,
      message: 'Marketplace purchase fetch is not implemented yet.',
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
}

class _BodyParseResult {
  const _BodyParseResult({required this.payload, required this.response});

  final Map<String, Object?>? payload;
  final Response? response;
}
