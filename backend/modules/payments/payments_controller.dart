import 'package:shelf/shelf.dart';
import 'package:shelf_router/shelf_router.dart';
import 'package:uuid/uuid.dart';

import '../../infra/request_context.dart';
import '../../server/http_utils.dart';
import 'payment_service.dart';

class PaymentsController {
  PaymentsController({required PaymentService paymentService, Uuid? uuid})
    : _paymentService = paymentService,
      _uuid = uuid ?? const Uuid();

  final PaymentService _paymentService;
  final Uuid _uuid;

  Router get router {
    final router = Router();
    router.post('/payments', _handleWebhook);
    return router;
  }

  Future<Response> _handleWebhook(Request request) async {
    final rawBody = await request.readAsString();
    try {
      final result = await _paymentService.handleWebhook(
        headers: request.headers,
        rawBody: rawBody,
      );
      return _ok(
        request,
        data: <String, Object?>{
          'provider': result.provider,
          'provider_event_id': result.providerEventId,
          'action': result.action,
          'duplicate': result.duplicate,
          'signature_valid': result.signatureValid,
        },
        headers: <String, String>{
          'x-payment-provider': result.provider,
          'x-webhook-action': result.action,
        },
      );
    } on PaymentWebhookSignatureException {
      return _error(
        request,
        401,
        errorCode: 'INVALID_WEBHOOK_SIGNATURE',
        message: 'Webhook signature verification failed',
        headers: <String, String>{
          'x-payment-provider': _paymentService.providerName,
          'x-webhook-action': 'signature_invalid',
        },
      );
    } on FormatException catch (error) {
      return _error(
        request,
        400,
        errorCode: 'VALIDATION_ERROR',
        message: error.message,
      );
    } catch (_) {
      return _error(
        request,
        500,
        errorCode: 'INTERNAL_ERROR',
        message: 'Unable to process webhook',
      );
    }
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
}
