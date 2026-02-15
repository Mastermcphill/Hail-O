import 'package:dart_jsonwebtoken/dart_jsonwebtoken.dart';
import 'package:shelf/shelf.dart';

import '../../infra/request_context.dart';
import '../../infra/token_service.dart';
import '../http_utils.dart';

Middleware authMiddleware(
  TokenService tokenService, {
  Set<String> publicPaths = const <String>{
    'auth/register',
    'auth/login',
    'health',
    'api/healthz',
  },
}) {
  return (Handler innerHandler) {
    return (Request request) {
      final path = request.url.path;
      if (publicPaths.contains(path)) {
        return innerHandler(request);
      }

      final authorization = request.headers['authorization']?.trim() ?? '';
      if (!authorization.startsWith('Bearer ')) {
        return Future<Response>.value(
          jsonErrorResponse(
            request,
            401,
            code: 'unauthorized',
            message: 'Missing bearer token',
          ),
        );
      }

      final token = authorization.substring('Bearer '.length).trim();
      if (token.isEmpty) {
        return Future<Response>.value(
          jsonErrorResponse(
            request,
            401,
            code: 'unauthorized',
            message: 'Missing bearer token',
          ),
        );
      }

      try {
        final payload = tokenService.verifyToken(token);
        final current = request.requestContext;
        final authed = RequestContext.withContext(
          request,
          current.copyWith(userId: payload.userId, role: payload.role),
        );
        return innerHandler(authed);
      } on JWTException {
        return Future<Response>.value(
          jsonErrorResponse(
            request,
            401,
            code: 'invalid_token',
            message: 'Bearer token is invalid or expired',
          ),
        );
      }
    };
  };
}
