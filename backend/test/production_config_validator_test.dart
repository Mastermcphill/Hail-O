import 'package:test/test.dart';

import '../infra/production_config_validator.dart';

void main() {
  test('does not enforce strict checks for development', () {
    expect(
      () => validateProductionConfig(
        environment: 'development',
        usePostgres: false,
        envMap: const <String, String>{},
      ),
      returnsNormally,
    );
  });

  test('requires JWT secret and allowed origins in staging/prod', () {
    expect(
      () => validateProductionConfig(
        environment: 'staging',
        usePostgres: false,
        envMap: const <String, String>{'JWT_SECRET': '', 'ALLOWED_ORIGINS': ''},
      ),
      throwsStateError,
    );
  });

  test('rejects wildcard allowed origins in strict env', () {
    expect(
      () => validateProductionConfig(
        environment: 'production',
        usePostgres: false,
        envMap: const <String, String>{
          'JWT_SECRET': 'super-secret',
          'ALLOWED_ORIGINS': '*',
          'SENTRY_DSN': 'https://public@sentry.io/1',
        },
      ),
      throwsStateError,
    );
  });

  test('requires sentry dsn in staging strict env', () {
    expect(
      () => validateProductionConfig(
        environment: 'staging',
        usePostgres: false,
        envMap: const <String, String>{
          'JWT_SECRET': 'super-secret',
          'ALLOWED_ORIGINS': 'https://app.hailo.dev',
          'SENTRY_DSN': '',
        },
      ),
      throwsStateError,
    );
  });

  test('requires sentry dsn in production when explicitly enabled', () {
    expect(
      () => validateProductionConfig(
        environment: 'production',
        usePostgres: false,
        envMap: const <String, String>{
          'JWT_SECRET': 'super-secret',
          'ALLOWED_ORIGINS': 'https://app.hailo.dev',
          'SENTRY_ENABLED': 'true',
          'SENTRY_DSN': '',
        },
      ),
      throwsA(
        isA<StateError>().having(
          (error) => error.toString(),
          'message',
          contains('SENTRY_DSN'),
        ),
      ),
    );
  });

  test('does not require sentry dsn in production when sentry is disabled', () {
    expect(
      () => validateProductionConfig(
        environment: 'production',
        usePostgres: false,
        envMap: const <String, String>{
          'JWT_SECRET': 'super-secret',
          'ALLOWED_ORIGINS': 'https://app.hailo.dev',
          'SENTRY_ENABLED': 'false',
          'SENTRY_DSN': '',
          'OTP_PROVIDER': 'termii',
          'TERMII_API_KEY': 'termii-key',
          'TERMII_SENDER_ID': 'HAILO',
        },
      ),
      returnsNormally,
    );
  });

  test('does not require sentry dsn in production when flag is unset', () {
    expect(
      () => validateProductionConfig(
        environment: 'production',
        usePostgres: false,
        envMap: const <String, String>{
          'JWT_SECRET': 'super-secret',
          'ALLOWED_ORIGINS': 'https://app.hailo.dev',
          'SENTRY_DSN': '',
          'OTP_PROVIDER': 'termii',
          'TERMII_API_KEY': 'termii-key',
          'TERMII_SENDER_ID': 'HAILO',
        },
      ),
      returnsNormally,
    );
  });

  test('requires OTP provider config in production', () {
    expect(
      () => validateProductionConfig(
        environment: 'production',
        usePostgres: false,
        envMap: const <String, String>{
          'JWT_SECRET': 'super-secret',
          'ALLOWED_ORIGINS': 'https://app.hailo.dev',
          'SENTRY_DSN': 'https://public@sentry.io/1',
        },
      ),
      throwsA(
        isA<StateError>().having(
          (error) => error.toString(),
          'message',
          contains('OTP_PROVIDER'),
        ),
      ),
    );
  });

  test('rejects OTP dev bypass in production', () {
    expect(
      () => validateProductionConfig(
        environment: 'production',
        usePostgres: false,
        envMap: const <String, String>{
          'JWT_SECRET': 'super-secret',
          'ALLOWED_ORIGINS': 'https://app.hailo.dev',
          'SENTRY_DSN': 'https://public@sentry.io/1',
          'OTP_PROVIDER': 'termii',
          'TERMII_API_KEY': 'termii-key',
          'TERMII_SENDER_ID': 'HAILO',
          'OTP_DEV_BYPASS': 'true',
        },
      ),
      throwsA(
        isA<StateError>().having(
          (error) => error.toString(),
          'message',
          contains('OTP_DEV_BYPASS'),
        ),
      ),
    );
  });

  test('requires redis url in production only when REDIS_ENABLED=true', () {
    expect(
      () => validateProductionConfig(
        environment: 'production',
        usePostgres: false,
        envMap: const <String, String>{
          'JWT_SECRET': 'super-secret',
          'ALLOWED_ORIGINS': 'https://app.hailo.dev',
          'OTP_PROVIDER': 'termii',
          'TERMII_API_KEY': 'termii-key',
          'TERMII_SENDER_ID': 'HAILO',
          'REDIS_ENABLED': 'true',
        },
      ),
      throwsA(
        isA<StateError>().having(
          (error) => error.toString(),
          'message',
          contains('REDIS_URL'),
        ),
      ),
    );
  });

  test('does not require redis url in production when REDIS_ENABLED=false', () {
    expect(
      () => validateProductionConfig(
        environment: 'production',
        usePostgres: false,
        envMap: const <String, String>{
          'JWT_SECRET': 'super-secret',
          'ALLOWED_ORIGINS': 'https://app.hailo.dev',
          'OTP_PROVIDER': 'termii',
          'TERMII_API_KEY': 'termii-key',
          'TERMII_SENDER_ID': 'HAILO',
          'REDIS_ENABLED': 'false',
        },
      ),
      returnsNormally,
    );
  });

  test('accepts complete strict config', () {
    expect(
      () => validateProductionConfig(
        environment: 'production',
        usePostgres: true,
        envMap: const <String, String>{
          'JWT_SECRET': 'super-secret',
          'ALLOWED_ORIGINS': 'https://app.hailo.dev,https://admin.hailo.dev',
          'DATABASE_URL': 'postgres://hailo:secret@localhost:5432/hailo',
          'SENTRY_DSN': 'https://public@sentry.io/1',
          'OTP_PROVIDER': 'termii',
          'TERMII_API_KEY': 'termii-key',
          'TERMII_SENDER_ID': 'HAILO',
          'REDIS_ENABLED': 'false',
        },
      ),
      returnsNormally,
    );
  });
}
