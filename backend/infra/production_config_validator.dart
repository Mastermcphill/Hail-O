const String _insecureJwtPlaceholder = 'dev-only-insecure-secret-change-me';

void validateProductionConfig({
  required String environment,
  required bool usePostgres,
  required Map<String, String> envMap,
}) {
  if (!_isStrictEnvironment(environment)) {
    return;
  }

  final missing = <String>[];
  final jwtSecret = (envMap['JWT_SECRET'] ?? '').trim();
  if (jwtSecret.isEmpty || jwtSecret == _insecureJwtPlaceholder) {
    missing.add('JWT_SECRET');
  }

  final allowedOrigins = _parseAllowedOrigins(envMap['ALLOWED_ORIGINS']);
  if (allowedOrigins.isEmpty || allowedOrigins.contains('*')) {
    missing.add('ALLOWED_ORIGINS');
  }
  final sentryDsn = (envMap['SENTRY_DSN'] ?? '').trim();
  if (sentryDsn.isEmpty) {
    missing.add('SENTRY_DSN');
  }

  if (usePostgres) {
    final databaseUrl = (envMap['DATABASE_URL'] ?? '').trim();
    if (databaseUrl.isEmpty) {
      missing.add('DATABASE_URL');
    }
  }

  if (missing.isEmpty) {
    return;
  }

  final normalizedEnv = environment.trim().toLowerCase();
  throw StateError(
    'Missing required config for $normalizedEnv: ${missing.join(', ')}',
  );
}

bool _isStrictEnvironment(String value) {
  final normalized = value.trim().toLowerCase();
  return normalized == 'production' ||
      normalized == 'prod' ||
      normalized == 'staging';
}

Set<String> _parseAllowedOrigins(String? value) {
  if (value == null || value.trim().isEmpty) {
    return <String>{};
  }
  return value
      .split(',')
      .map((item) => item.trim())
      .where((item) => item.isNotEmpty)
      .toSet();
}
