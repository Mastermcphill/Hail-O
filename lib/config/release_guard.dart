import 'package:flutter/foundation.dart';

import 'api_config.dart';

class ReleaseGuardIssue {
  const ReleaseGuardIssue({required this.code, required this.message});

  final String code;
  final String message;
}

class ReleaseGuardResult {
  const ReleaseGuardResult({required this.issues});

  final List<ReleaseGuardIssue> issues;

  bool get isValid => issues.isEmpty;
}

class ReleaseGuard {
  ReleaseGuard._();

  static const bool _allowReleaseDev = bool.fromEnvironment(
    'HAILO_ALLOW_RELEASE_DEV',
    defaultValue: false,
  );
  static const bool _allowInsecureReleaseBaseUrl = bool.fromEnvironment(
    'HAILO_ALLOW_INSECURE_RELEASE_BASE_URL',
    defaultValue: false,
  );
  static const String _release = String.fromEnvironment(
    'HAILO_RELEASE',
    defaultValue: 'local',
  );
  static const String _sentryDsn = String.fromEnvironment(
    'SENTRY_DSN',
    defaultValue: '',
  );

  static void enforceInRelease() {
    if (!kReleaseMode) {
      return;
    }
    final result = evaluate(
      environmentName: ApiConfig.environmentName,
      baseUrl: ApiConfig.baseUrl,
      release: _release,
      sentryDsn: _sentryDsn,
      allowReleaseDev: _allowReleaseDev,
      allowInsecureBaseUrl: _allowInsecureReleaseBaseUrl,
    );
    if (result.isValid) {
      return;
    }
    final joined = result.issues
        .map((issue) => '${issue.code}: ${issue.message}')
        .join('; ');
    throw StateError('Release guard failed: $joined');
  }

  @visibleForTesting
  static ReleaseGuardResult evaluate({
    required String environmentName,
    required String baseUrl,
    required String release,
    required String sentryDsn,
    required bool allowReleaseDev,
    required bool allowInsecureBaseUrl,
  }) {
    final issues = <ReleaseGuardIssue>[];
    final environment = environmentName.trim().toLowerCase();
    final normalizedRelease = release.trim();
    final normalizedBaseUrl = baseUrl.trim();
    final parsed = Uri.tryParse(normalizedBaseUrl);

    if (environment == 'dev' && !allowReleaseDev) {
      issues.add(
        const ReleaseGuardIssue(
          code: 'release_env_dev_forbidden',
          message:
              'Release builds must not run with HAILO_ENV=dev unless HAILO_ALLOW_RELEASE_DEV=true.',
        ),
      );
    }

    if (normalizedRelease.isEmpty || normalizedRelease == 'local') {
      issues.add(
        const ReleaseGuardIssue(
          code: 'release_id_missing',
          message:
              'HAILO_RELEASE must be provided for release builds (non-local).',
        ),
      );
    }

    if (parsed == null) {
      issues.add(
        const ReleaseGuardIssue(
          code: 'base_url_invalid',
          message: 'HAILO_BASE_URL/derived base URL is not a valid URI.',
        ),
      );
    } else {
      final isHttps = parsed.scheme.toLowerCase() == 'https';
      if (!isHttps && !allowInsecureBaseUrl) {
        issues.add(
          const ReleaseGuardIssue(
            code: 'base_url_insecure',
            message:
                'Release builds must use HTTPS base URL unless HAILO_ALLOW_INSECURE_RELEASE_BASE_URL=true.',
          ),
        );
      }

      const blockedHosts = <String>{'localhost', '127.0.0.1', '10.0.2.2'};
      if (blockedHosts.contains(parsed.host.toLowerCase()) &&
          !allowReleaseDev) {
        issues.add(
          const ReleaseGuardIssue(
            code: 'base_url_localhost_forbidden',
            message:
                'Release builds cannot target localhost/emulator hosts unless HAILO_ALLOW_RELEASE_DEV=true.',
          ),
        );
      }

      if (environment == HailoEnvironment.prod.name &&
          parsed.host.toLowerCase().contains('staging')) {
        issues.add(
          const ReleaseGuardIssue(
            code: 'base_url_staging_forbidden',
            message: 'Production releases must not target staging base URLs.',
          ),
        );
      }
    }

    if ((environment == HailoEnvironment.staging.name ||
            environment == HailoEnvironment.prod.name) &&
        sentryDsn.trim().isEmpty) {
      issues.add(
        const ReleaseGuardIssue(
          code: 'sentry_dsn_missing',
          message: 'SENTRY_DSN is required for staging/prod release builds.',
        ),
      );
    }

    return ReleaseGuardResult(issues: issues);
  }
}
