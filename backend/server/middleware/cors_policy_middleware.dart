import 'package:shelf/shelf.dart';

import '../../infra/request_context.dart';
import '../http_utils.dart';

Set<String> parseAllowedOrigins(String? value) {
  if (value == null || value.trim().isEmpty) {
    return <String>{};
  }
  return value
      .split(',')
      .map((item) => item.trim())
      .where((item) => item.isNotEmpty)
      .toSet();
}

Middleware corsPolicyMiddleware({
  required Set<String> allowedOrigins,
  Set<String> allowedMethods = const <String>{'GET', 'POST', 'OPTIONS'},
  Set<String> allowedHeaders = const <String>{
    'Authorization',
    'Idempotency-Key',
    'X-Trace-Id',
    'Content-Type',
  },
}) {
  final methodsHeader = allowedMethods.join(', ');
  final headersHeader = allowedHeaders.join(', ');

  return (Handler innerHandler) {
    return (Request request) async {
      final origin = request.headers['origin']?.trim();
      final method = request.method.toUpperCase();
      final isPreflight =
          method == 'OPTIONS' &&
          request.headers.containsKey('access-control-request-method');

      if (origin != null && origin.isNotEmpty) {
        if (!allowedOrigins.contains(origin)) {
          return jsonResponse(403, <String, Object?>{
            'code': 'cors_origin_denied',
            'message': 'Origin is not allowed',
            'trace_id': request.requestContext.traceId,
          });
        }

        if (isPreflight) {
          return Response(
            204,
            headers: <String, String>{
              'access-control-allow-origin': origin,
              'access-control-allow-methods': methodsHeader,
              'access-control-allow-headers': headersHeader,
              'vary': 'origin',
            },
          );
        }

        final response = await innerHandler(request);
        return response.change(
          headers: <String, String>{
            ...response.headers,
            'access-control-allow-origin': origin,
            'access-control-allow-methods': methodsHeader,
            'access-control-allow-headers': headersHeader,
            'vary': 'origin',
          },
        );
      }

      if (isPreflight) {
        return jsonResponse(403, <String, Object?>{
          'code': 'cors_origin_denied',
          'message': 'Origin is required',
          'trace_id': request.requestContext.traceId,
        });
      }

      return innerHandler(request);
    };
  };
}
