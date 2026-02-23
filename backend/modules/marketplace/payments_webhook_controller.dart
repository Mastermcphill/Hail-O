import 'dart:convert';

import 'package:shelf/shelf.dart';
import 'package:shelf_router/shelf_router.dart';

import '../../infra/request_context.dart';
import '../../infra/request_metrics.dart';
import 'marketplace_envelope.dart';
import 'payment_service.dart';

class PaymentsWebhookController {
  PaymentsWebhookController({
    required PaymentService paymentService,
    required RequestMetrics requestMetrics,
    void Function(String line)? logSink,
  }) : _paymentService = paymentService,
       _requestMetrics = requestMetrics,
       _logSink = logSink ?? print;

  final PaymentService _paymentService;
  final RequestMetrics _requestMetrics;
  final void Function(String line) _logSink;

  Router get router {
    final router = Router();
    router.post('/payments', _handleWebhook);
    return router;
  }

  Future<Response> _handleWebhook(Request request) async {
    final watch = Stopwatch()..start();
    var statusCode = 500;
    var purchaseId = '';
    var action = 'failed';
    try {
      final outcome = await _paymentService.handleWebhook(request);
      statusCode = outcome.statusCode;
      action = outcome.action;
      purchaseId = (outcome.data['purchase_id'] as String?) ?? '';
      if (!outcome.success) {
        return marketplaceError(
          request,
          statusCode: outcome.statusCode,
          errorCode: 'WEBHOOK_VERIFICATION_FAILED',
          message: outcome.message,
        );
      }
      return marketplaceOk(
        request,
        statusCode: outcome.statusCode,
        data: <String, Object?>{'action': outcome.action, ...outcome.data},
      );
    } catch (_) {
      statusCode = 500;
      action = 'failed';
      _requestMetrics.recordMarketplacePaymentFailure();
      return marketplaceError(
        request,
        statusCode: 500,
        errorCode: 'INTERNAL_ERROR',
        message: 'Failed to process webhook',
      );
    } finally {
      watch.stop();
      _requestMetrics.recordMarketplaceRequest(
        route: '/webhooks/payments',
        method: request.method,
        statusCode: statusCode,
        latencyMs: watch.elapsedMilliseconds,
      );
      _logSink(
        jsonEncode(<String, Object?>{
          'trace_id': request.requestContext.traceId,
          'route': '/webhooks/payments',
          'method': request.method,
          'status_code': statusCode,
          'latency_ms': watch.elapsedMilliseconds,
          'action': action,
          if (purchaseId.isNotEmpty) 'purchase_id': purchaseId,
        }),
      );
    }
  }
}
