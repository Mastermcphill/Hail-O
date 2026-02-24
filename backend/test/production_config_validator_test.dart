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

  test('requires sentry dsn in strict env', () {
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
        },
      ),
      returnsNormally,
    );
  });
}
