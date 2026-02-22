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
      metrics.record(statusCode: response.statusCode, errorCode: errorCode);

      sink(
        jsonEncode(<String, Object?>{
          'trace_id': request.requestContext.traceId,
          'method': request.method,
          'path': request.url.path,
          'status': response.statusCode,
          'latency_ms': watch.elapsedMilliseconds,
          'user_id': request.requestContext.userId,
          'idempotency_key': _hashIdempotencyKey(
            request.requestContext.idempotencyKey,
          ),
          if (errorCode != null && errorCode.isNotEmpty)
            'error_code': errorCode,
        }),
      );
      return response;
    };
  };
}

String? _hashIdempotencyKey(String? key) {
  if (key == null || key.isEmpty) {
    return null;
  }
  final digest = sha256.convert(utf8.encode(key)).toString();
  return digest.substring(0, 16);
}
