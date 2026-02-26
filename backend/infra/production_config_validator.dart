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
  final otpProvider = (_getOptionalTrimmed(envMap, 'OTP_PROVIDER') ?? '')
      .toLowerCase();
  final otpDevBypass = _parseBool(envMap['OTP_DEV_BYPASS']);
  final termiiApiKey = _getOptionalTrimmed(envMap, 'TERMII_API_KEY');
  final termiiSenderId = _getOptionalTrimmed(envMap, 'TERMII_SENDER_ID');
  final redisUrl = _getOptionalTrimmed(envMap, 'REDIS_URL');
  final otpProviderSupported =
      otpProvider.isEmpty ||
      otpProvider == 'termii' ||
      otpProvider == 'none' ||
      otpProvider == 'disabled';
  if (!otpProviderSupported) {
    missing.add('OTP_PROVIDER');
  }
  final hasOtpProviderConfig =
      otpProvider == 'termii' && termiiApiKey != null && termiiSenderId != null;

  if (isProductionEnv) {
    if (redisUrl == null) {
      missing.add('REDIS_URL');
    }
    if (sentryEnabled && sentryDsn == null) {
      missing.add('SENTRY_DSN');
    } else if (!sentryEnabled && sentryDsn == null) {
      stderr.writeln(
        'WARN: SENTRY_DSN not set; Sentry is disabled. Set SENTRY_ENABLED=true and SENTRY_DSN to enable error reporting.',
      );
    }
    if (!hasOtpProviderConfig) {
      missing.add('OTP_PROVIDER');
      missing.add('TERMII_API_KEY');
      missing.add('TERMII_SENDER_ID');
    }
    if (otpDevBypass) {
      missing.add('OTP_DEV_BYPASS');
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
    'Missing required config for $normalizedEnv: ${missing.toSet().join(', ')}',
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
