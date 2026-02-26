import 'dart:convert';

import 'package:shelf/shelf.dart';

import '../../infra/request_context.dart';

const String _defaultEmergencyActorUserId = 'admin-token-emergency';

Middleware adminEmergencyAccessMiddleware({
  required String adminToken,
  Set<String> adminPathPrefixes = const <String>{'admin/', 'admin'},
}) {
  final normalizedAdminToken = adminToken.trim();
  if (normalizedAdminToken.isEmpty) {
    return (Handler innerHandler) => innerHandler;
  }

  return (Handler innerHandler) {
    return (Request request) {
      final path = _canonicalPath(request.url.path);
      if (!_isAdminPath(path, adminPathPrefixes)) {
        return innerHandler(request);
      }

      final providedToken = _resolveProvidedAdminToken(request.headers);
      if (providedToken.isEmpty ||
          !_constantTimeEquals(providedToken, normalizedAdminToken)) {
        return innerHandler(request);
      }

      final current = request.requestContext;
      final emergencyRequest = RequestContext.withContext(
        request,
        current.copyWith(
          userId: (current.userId?.trim().isNotEmpty ?? false)
              ? current.userId
              : _defaultEmergencyActorUserId,
          role: 'admin',
        ),
      );
      return innerHandler(emergencyRequest);
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

bool _isAdminPath(String path, Set<String> adminPathPrefixes) {
  for (final prefix in adminPathPrefixes) {
    if (path == prefix || path.startsWith(prefix)) {
      return true;
    }
  }
  return false;
}

String _resolveProvidedAdminToken(Map<String, String> headers) {
  final direct = (headers['admin_token'] ?? '').trim();
  if (direct.isNotEmpty) {
    return direct;
  }
  final dash = (headers['admin-token'] ?? '').trim();
  if (dash.isNotEmpty) {
    return dash;
  }
  final xDash = (headers['x-admin-token'] ?? '').trim();
  if (xDash.isNotEmpty) {
    return xDash;
  }
  final base64Header = (headers['x-admin-token-base64'] ?? '').trim();
  if (base64Header.isNotEmpty) {
    try {
      return utf8.decode(base64.decode(base64Header));
    } catch (_) {
      return '';
    }
  }
  return '';
}

bool _constantTimeEquals(String left, String right) {
  if (left.length != right.length) {
    return false;
  }
  var result = 0;
  for (var index = 0; index < left.length; index++) {
    result |= left.codeUnitAt(index) ^ right.codeUnitAt(index);
  }
  return result == 0;
}
