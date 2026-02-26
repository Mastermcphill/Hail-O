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
    'healthz',
  },
  Set<String> publicPrefixes = const <String>{'marketplace/offers/'},
  Set<String> protectedPrefixes = const <String>{
    'rides/',
    'me',
    'me/',
    'routes/',
    'drivers/',
    'settlement/',
    'disputes',
    'marketplace/',
    'payments/',
    'orgs',
    'orgs/',
    'admin/',
    'metrics',
  },
}) {
  return (Handler innerHandler) {
    return (Request request) {
      final path = _canonicalPath(request.url.path);
      if (publicPaths.contains(path) || _isPublicPath(path, publicPrefixes)) {
        return innerHandler(request);
      }

      // RequestContext can be injected by internal pipelines/tests.
      if ((request.requestContext.userId ?? '').trim().isNotEmpty) {
        return innerHandler(request);
      }
      if (!_isProtectedPath(path, protectedPrefixes)) {
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

String _canonicalPath(String path) {
  final trimmed = path.trim();
  if (trimmed == 'api') {
    return '';
  }
  if (trimmed.startsWith('api/')) {
    return trimmed.substring(4);
  }
  return trimmed;
}

bool _isPublicPath(String path, Set<String> publicPrefixes) {
  if (path == 'marketplace/offers') {
    return true;
  }
  for (final prefix in publicPrefixes) {
    if (path.startsWith(prefix)) {
      return true;
    }
  }
  return false;
}

bool _isProtectedPath(String path, Set<String> protectedPrefixes) {
  for (final prefix in protectedPrefixes) {
    if (path == prefix || path.startsWith(prefix)) {
      return true;
    }
  }
  return false;
}
