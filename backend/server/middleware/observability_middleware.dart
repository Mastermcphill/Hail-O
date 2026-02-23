import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:shelf/shelf.dart';

import '../../infra/request_context.dart';
import '../../infra/request_metrics.dart';

Middleware observabilityMiddleware({
  required RequestMetrics metrics,
  void Function(String line)? logSink,
}) {
  final sink = logSink ?? print;
  return (Handler innerHandler) {
    return (Request request) async {
      final watch = Stopwatch()..start();
      final response = await innerHandler(request);
      watch.stop();

      final errorCode = response.headers['x-error-code'];
      final latencyMs = watch.elapsedMilliseconds;
      final path = request.url.path;

      metrics.record(statusCode: response.statusCode, errorCode: errorCode);

      // Suppress high-frequency healthz probes to keep logs signal-rich.
      if (_shouldSuppressRequestLog(path)) {
        return response;
      }

      final webhookProvider = response.headers['x-payment-provider'] ?? '';
      final webhookAction = response.headers['x-webhook-action'] ?? '';

      sink(
        jsonEncode(<String, Object?>{
          'trace_id': request.requestContext.traceId,
          'route': path,
          'method': request.method,
          'status_code': response.statusCode,
          'latency_ms': latencyMs,
          'user_id': request.requestContext.userId,
          'idempotency_key': _hashIdempotencyKey(
            request.requestContext.idempotencyKey,
          ),
          'purchase_id':
              response.headers['x-marketplace-purchase-id'] ??
              _extractPurchaseIdFromPath(request.url.pathSegments),
          if (errorCode != null && errorCode.isNotEmpty)
            'error_code': errorCode,
          if (webhookProvider.isNotEmpty) 'webhook_provider': webhookProvider,
          if (webhookAction.isNotEmpty) 'webhook_action': webhookAction,
        }),
      );
      return response;
    };
  };
}

bool _shouldSuppressRequestLog(String path) {
  return path == 'healthz' || path == 'api/healthz';
}

String? _hashIdempotencyKey(String? key) {
  if (key == null || key.isEmpty) {
    return null;
  }
  final digest = sha256.convert(utf8.encode(key)).toString();
  return digest.substring(0, 16);
}

String? _extractPurchaseIdFromPath(List<String> pathSegments) {
  for (final segment in pathSegments) {
    final trimmed = segment.trim();
    if (trimmed.length == 36 && trimmed.contains('-')) {
      return trimmed;
    }
  }
  return null;
}
