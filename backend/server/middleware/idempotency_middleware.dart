import 'package:shelf/shelf.dart';

import '../../infra/request_context.dart';
import '../http_utils.dart';

const String _headerIdempotencyKey = 'idempotency-key';

Middleware idempotencyMiddleware({
  Set<String> exemptWritePaths = const <String>{'auth/login'},
}) {
  return (Handler innerHandler) {
    return (Request request) {
      if (request.method.toUpperCase() != 'POST') {
        return innerHandler(request);
      }

      final path = request.url.path;
      if (exemptWritePaths.contains(path)) {
        return innerHandler(request);
      }

      final idempotencyKey =
          request.headers[_headerIdempotencyKey]?.trim() ?? '';
      if (idempotencyKey.isEmpty) {
        return Future<Response>.value(
          jsonErrorResponse(
            request,
            400,
            code: 'missing_idempotency_key',
            message: 'Idempotency-Key header is required for write requests',
          ),
        );
      }

      final current = request.requestContext;
      final withIdempotency = RequestContext.withContext(
        request,
        current.copyWith(idempotencyKey: idempotencyKey),
      );
      return innerHandler(withIdempotency);
    };
  };
}
