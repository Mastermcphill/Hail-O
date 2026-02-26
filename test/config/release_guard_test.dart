import 'package:flutter_test/flutter_test.dart';
import 'package:hailo_core/config/release_guard.dart';

void main() {
  test('release guard passes for valid prod config', () {
    final result = ReleaseGuard.evaluate(
      environmentName: 'prod',
      baseUrl: 'https://api.hailo.example',
      release: '1.0.0+100',
      sentryDsn: 'https://examplePublicKey@o0.ingest.sentry.io/0',
      allowReleaseDev: false,
      allowInsecureBaseUrl: false,
    );

    expect(result.isValid, isTrue);
    expect(result.issues, isEmpty);
  });

  test('release guard fails when release metadata is local', () {
    final result = ReleaseGuard.evaluate(
      environmentName: 'prod',
      baseUrl: 'https://api.hailo.example',
      release: 'local',
      sentryDsn: 'https://examplePublicKey@o0.ingest.sentry.io/0',
      allowReleaseDev: false,
      allowInsecureBaseUrl: false,
    );

    expect(result.isValid, isFalse);
    expect(
      result.issues.any((issue) => issue.code == 'release_id_missing'),
      isTrue,
    );
  });

  test('release guard fails for localhost base URL in release mode', () {
    final result = ReleaseGuard.evaluate(
      environmentName: 'staging',
      baseUrl: 'http://10.0.2.2:8080',
      release: '1.2.0+3',
      sentryDsn: 'https://examplePublicKey@o0.ingest.sentry.io/0',
      allowReleaseDev: false,
      allowInsecureBaseUrl: false,
    );

    expect(result.isValid, isFalse);
    expect(
      result.issues.any(
        (issue) => issue.code == 'base_url_localhost_forbidden',
      ),
      isTrue,
    );
  });

  test('release guard requires sentry dsn in strict environments', () {
    final result = ReleaseGuard.evaluate(
      environmentName: 'prod',
      baseUrl: 'https://api.hailo.example',
      release: '1.2.0+3',
      sentryDsn: '',
      allowReleaseDev: false,
      allowInsecureBaseUrl: false,
    );

    expect(result.isValid, isFalse);
    expect(
      result.issues.any((issue) => issue.code == 'sentry_dsn_missing'),
      isTrue,
    );
  });

  test('release guard blocks staging hosts in prod releases', () {
    final result = ReleaseGuard.evaluate(
      environmentName: 'prod',
      baseUrl: 'https://staging-api.hailo.example',
      release: '1.2.0+3',
      sentryDsn: 'https://examplePublicKey@o0.ingest.sentry.io/0',
      allowReleaseDev: false,
      allowInsecureBaseUrl: false,
    );

    expect(result.isValid, isFalse);
    expect(
      result.issues.any((issue) => issue.code == 'base_url_staging_forbidden'),
      isTrue,
    );
  });
}
