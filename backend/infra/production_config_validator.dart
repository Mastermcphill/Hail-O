import 'dart:io';

const String _insecureJwtPlaceholder = 'dev-only-insecure-secret-change-me';

void validateProductionConfig({
  required String environment,
  required bool usePostgres,
  required Map<String, String> envMap,
}) {
  final normalizedEnv = environment.trim().toLowerCase();
  if (!_isStrictEnvironment(normalizedEnv)) {
    return;
  }

  final missing = <String>[];
  final jwtSecret = _getOptionalTrimmed(envMap, 'JWT_SECRET') ?? '';
  if (jwtSecret.isEmpty || jwtSecret == _insecureJwtPlaceholder) {
    missing.add('JWT_SECRET');
  }

  final allowedOrigins = _parseAllowedOrigins(envMap['ALLOWED_ORIGINS']);
  if (allowedOrigins.isEmpty || allowedOrigins.contains('*')) {
    missing.add('ALLOWED_ORIGINS');
  }
  final sentryEnabled = _parseBool(envMap['SENTRY_ENABLED']);
  final sentryDsn = _getOptionalTrimmed(envMap, 'SENTRY_DSN');
  final isProductionEnv =
      normalizedEnv == 'production' || normalizedEnv == 'prod';
  if (isProductionEnv) {
    if (sentryEnabled && sentryDsn == null) {
      missing.add('SENTRY_DSN');
    } else if (!sentryEnabled && sentryDsn == null) {
      stderr.writeln(
        'WARN: SENTRY_DSN not set; Sentry is disabled. Set SENTRY_ENABLED=true and SENTRY_DSN to enable error reporting.',
      );
    }
  } else if (sentryDsn == null) {
    missing.add('SENTRY_DSN');
  }

  if (usePostgres) {
    final databaseUrl = _getOptionalTrimmed(envMap, 'DATABASE_URL');
    if (databaseUrl == null) {
      missing.add('DATABASE_URL');
    }
  }

  if (missing.isEmpty) {
    return;
  }

  throw StateError(
    'Missing required config for $normalizedEnv: ${missing.join(', ')}',
  );
}

bool _isStrictEnvironment(String value) {
  return value == 'production' || value == 'prod' || value == 'staging';
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

String? _getOptionalTrimmed(Map<String, String> envMap, String key) {
  final value = envMap[key]?.trim();
  if (value == null || value.isEmpty) {
    return null;
  }
  return value;
}

bool _parseBool(String? value) {
  final normalized = value?.trim().toLowerCase() ?? '';
  return normalized == '1' ||
      normalized == 'true' ||
      normalized == 'yes' ||
      normalized == 'y' ||
      normalized == 'on';
}
