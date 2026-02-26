const String bootPath = '/boot';

const Set<String> publicAuthPaths = <String>{
  '/',
  '/login',
  '/signup',
  '/admin-login',
};

bool isPublicPath(String path) {
  return publicAuthPaths.contains(path);
}

String normalizeRole(String? role) {
  final normalized = (role ?? '').trim().toLowerCase();
  if (normalized == 'fleet') {
    return 'fleet_owner';
  }
  if (normalized.isEmpty) {
    return 'rider';
  }
  return normalized;
}

bool isSelectedPath(String currentPath, String itemPath) {
  return currentPath == itemPath || currentPath.startsWith('$itemPath/');
}

String? roleFromPath(String path) {
  if (isSelectedPath(path, '/home')) {
    return 'rider';
  }
  if (isSelectedPath(path, '/rider')) {
    return 'rider';
  }
  if (isSelectedPath(path, '/marketplace')) {
    return 'rider';
  }
  if (isSelectedPath(path, '/dispatch')) {
    return 'rider';
  }
  if (isSelectedPath(path, '/driver')) {
    return 'driver';
  }
  if (isSelectedPath(path, '/fleet')) {
    return 'fleet_owner';
  }
  if (isSelectedPath(path, '/admin')) {
    return 'admin';
  }
  return null;
}

bool isRoleRoute(String path) {
  return roleFromPath(path) != null;
}

bool isRoleAllowed(String path, String role) {
  final routeRole = roleFromPath(path);
  if (routeRole == null) {
    return true;
  }
  return normalizeRole(role) == routeRole;
}

String homeRouteForRole(String role) {
  switch (normalizeRole(role)) {
    case 'driver':
      return '/driver';
    case 'fleet_owner':
      return '/fleet';
    case 'admin':
      return '/admin';
    case 'rider':
    default:
      return '/rider';
  }
}

String buildAuthRedirectPath({
  required String requestedPath,
  required Uri requestedUri,
}) {
  final encodedNext = Uri.encodeQueryComponent(requestedUri.toString());
  if (isSelectedPath(requestedPath, '/admin')) {
    return '/admin-login?next=$encodedNext';
  }
  return '/login?next=$encodedNext';
}

String resolvePostLoginRoute({required String role, String? nextPath}) {
  final fallback = homeRouteForRole(role);
  final rawNext = (nextPath ?? '').trim();
  if (rawNext.isEmpty) {
    return fallback;
  }

  final decodedNext = Uri.decodeComponent(rawNext);
  final nextUri = Uri.tryParse(decodedNext);
  if (nextUri == null) {
    return fallback;
  }
  final nextRoutePath = nextUri.path.trim();
  if (nextRoutePath.isEmpty || nextRoutePath == bootPath) {
    return fallback;
  }
  if (isPublicPath(nextRoutePath)) {
    return fallback;
  }
  if (isRoleRoute(nextRoutePath) &&
      !isRoleAllowed(nextRoutePath, normalizeRole(role))) {
    return fallback;
  }
  return nextUri.toString();
}
