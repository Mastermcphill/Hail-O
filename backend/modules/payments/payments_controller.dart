import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:shelf/shelf.dart';
import 'package:shelf_router/shelf_router.dart';
import 'package:uuid/uuid.dart';

import '../../infra/request_context.dart';
import '../../server/http_utils.dart';
import 'payment_intent_repository.dart';
import 'payment_service.dart';

class PaymentsController {
  PaymentsController({
    required PaymentService paymentService,
    String environment = 'development',
    String webhookSecret = '',
    void Function(String line)? warningSink,
    Uuid? uuid,
  }) : _paymentService = paymentService,
       _environment = environment,
       _webhookSecret = webhookSecret,
       _warningSink = warningSink ?? stderr.writeln,
       _uuid = uuid ?? const Uuid();

  final PaymentService _paymentService;
  final String _environment;
  final String _webhookSecret;
  final void Function(String line) _warningSink;
  final Uuid _uuid;
  bool _missingSecretWarningLogged = false;

  Router get webhookRouter {
    final router = Router();
    router.post('/payments', _handleWebhook);
    return router;
  }

  Router get intentsRouter {
    final router = Router();
    router.post('/intents', _createIntent);
    router.get('/intents/<intentId>', _getIntent);
    return router;
  }

  Future<Response> _handleWebhook(Request request) async {
    final rawBody = await request.readAsString();
    final secretPolicyResponse = _validateWebhookSecretPolicy(
      request: request,
      rawBody: rawBody,
    );
    if (secretPolicyResponse != null) {
      return secretPolicyResponse;
    }
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

  Response? _validateWebhookSecretPolicy({
    required Request request,
    required String rawBody,
  }) {
    final secret = _webhookSecret.trim();
    if (secret.isEmpty) {
      if (_isProductionEnvironment()) {
        return _error(
          request,
          503,
          errorCode: 'WEBHOOK_CONFIG_ERROR',
          message:
              'PAYMENTS_WEBHOOK_SECRET is required in production for webhook verification',
        );
      }
      if (!_missingSecretWarningLogged) {
        _missingSecretWarningLogged = true;
        _warningSink(
          'WARN: PAYMENTS_WEBHOOK_SECRET not set; webhook signature checks are disabled outside production.',
        );
      }
      return null;
    }

    final providedSignature = (request.headers['x-webhook-signature'] ?? '')
        .trim();
    if (providedSignature.isEmpty) {
      return _error(
        request,
        401,
        errorCode: 'INVALID_WEBHOOK_SIGNATURE',
        message: 'Missing x-webhook-signature header',
      );
    }
    final expectedSignature = Hmac(
      sha256,
      utf8.encode(secret),
    ).convert(utf8.encode(rawBody)).toString();
    if (expectedSignature.toLowerCase() != providedSignature.toLowerCase()) {
      return _error(
        request,
        401,
        errorCode: 'INVALID_WEBHOOK_SIGNATURE',
        message: 'Webhook signature verification failed',
      );
    }
    return null;
  }

  bool _isProductionEnvironment() {
    final normalized = _environment.trim().toLowerCase();
    return normalized == 'production' || normalized == 'prod';
  }

  Future<Response> _createIntent(Request request) async {
    final userId = request.requestContext.userId?.trim() ?? '';
    if (userId.isEmpty) {
      return _error(
        request,
        401,
        errorCode: 'UNAUTHORIZED',
        message: 'Bearer token required',
      );
    }

    try {
      final payload = await readJsonBody(request);
      final purchaseId =
          (payload['purchase_id'] as String?)?.trim() ??
          (payload['purchaseId'] as String?)?.trim() ??
          '';
      final intent = await _paymentService.createPaymentIntent(
        userId: userId,
        purchaseId: purchaseId,
      );
      return _ok(request, data: _intentPayload(intent));
    } on FormatException catch (error) {
      return _error(
        request,
        400,
        errorCode: 'VALIDATION_ERROR',
        message: error.message,
      );
    } on PaymentIntentPurchaseNotFoundException {
      return _error(
        request,
        404,
        errorCode: 'NOT_FOUND',
        message: 'Purchase not found',
      );
    } on PaymentIntentPurchaseStateException {
      return _error(
        request,
        409,
        errorCode: 'CONFLICT',
        message: 'Purchase is not pending_payment',
      );
    } catch (_) {
      return _error(
        request,
        500,
        errorCode: 'INTERNAL_ERROR',
        message: 'Unable to create payment intent',
      );
    }
  }

  Future<Response> _getIntent(Request request, String intentId) async {
    final userId = request.requestContext.userId?.trim() ?? '';
    if (userId.isEmpty) {
      return _error(
        request,
        401,
        errorCode: 'UNAUTHORIZED',
        message: 'Bearer token required',
      );
    }

    final intent = await _paymentService.getPaymentIntentForUser(
      userId: userId,
      intentId: intentId,
    );
    if (intent == null) {
      return _error(
        request,
        404,
        errorCode: 'NOT_FOUND',
        message: 'Payment intent not found',
      );
    }
    return _ok(request, data: _intentPayload(intent));
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

  Map<String, Object?> _intentPayload(PaymentIntentRecord intent) {
    final data = <String, Object?>{
      'id': intent.id,
      'status': intent.status,
      'amount_minor': intent.amountMinor,
      'currency': intent.currency,
      'provider': intent.provider,
    };
    final clientSecret = (intent.clientSecret ?? '').trim();
    if (clientSecret.isNotEmpty) {
      data['client_secret'] = clientSecret;
    }
    return data;
  }
}
