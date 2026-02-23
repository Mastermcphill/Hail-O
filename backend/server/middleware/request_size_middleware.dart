import 'package:shelf/shelf.dart';

import '../http_utils.dart';

Middleware requestSizeMiddleware({
  int maxBytes = 262144,
  Set<String> exemptPaths = const <String>{'health', 'healthz', 'api/healthz'},
}) {
  final safeMaxBytes = maxBytes > 0 ? maxBytes : 262144;

  return (Handler innerHandler) {
    return (Request request) {
      final path = request.url.path;
      if (exemptPaths.contains(path)) {
        return innerHandler(request);
      }

      final method = request.method.toUpperCase();
      final isWrite = method == 'POST' || method == 'PUT' || method == 'PATCH';
      if (!isWrite) {
        return innerHandler(request);
      }

      final contentLengthRaw = request.headers['content-length']?.trim();
      if (contentLengthRaw != null && contentLengthRaw.isNotEmpty) {
        final contentLength = int.tryParse(contentLengthRaw);
        if (contentLength != null && contentLength > safeMaxBytes) {
          return Future<Response>.value(
            jsonErrorResponse(
              request,
              413,
              code: 'request_body_too_large',
              message: 'Request body exceeds size limit',
            ),
          );
        }
      }

      return innerHandler(request);
    };
  };
}
