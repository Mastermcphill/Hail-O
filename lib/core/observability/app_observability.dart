import 'dart:async';
import 'dart:developer' as developer;

import 'package:flutter/foundation.dart';
import 'package:sentry_flutter/sentry_flutter.dart';

class AppObservability {
  AppObservability._();

  static final RegExp _emailPattern = RegExp(
    r'[A-Z0-9._%+-]+@[A-Z0-9.-]+\.[A-Z]{2,}',
    caseSensitive: false,
  );
  static final RegExp _phonePattern = RegExp(
    r'(?<!\d)(?:\+?\d[\d .()\-\u00A0]{7,}\d)',
  );
  static final ValueNotifier<String?> _lastRequestIdNotifier =
      ValueNotifier<String?>(null);
  static final ValueNotifier<String?> _lastTraceIdNotifier =
      ValueNotifier<String?>(null);

  static ValueListenable<String?> get lastRequestIdListenable =>
      _lastRequestIdNotifier;
  static String? get lastRequestId => _lastRequestIdNotifier.value;
  static ValueListenable<String?> get lastTraceIdListenable =>
      _lastTraceIdNotifier;
  static String? get lastTraceId => _lastTraceIdNotifier.value;

  static Future<void> recordHttpRequest({
    required String requestId,
    required String method,
    required Uri uri,
    required int attempt,
  }) async {
    _lastRequestIdNotifier.value = requestId;
    await Sentry.configureScope((scope) async {
      await scope.setTag('request_id', requestId);
    });
    await Sentry.addBreadcrumb(
      Breadcrumb(
        type: 'http',
        category: 'http',
        message: 'HTTP ${method.toUpperCase()} ${uri.path}',
        data: <String, dynamic>{
          'request_id': requestId,
          'method': method.toUpperCase(),
          'uri': scrubText(uri.toString()),
          'attempt': attempt + 1,
        },
        level: SentryLevel.info,
      ),
    );
  }

  static Future<void> recordHttpResponse({
    required String requestId,
    String? traceId,
    int? statusCode,
  }) async {
    final normalizedTraceId = (traceId ?? '').trim();
    if (normalizedTraceId.isNotEmpty) {
      _lastTraceIdNotifier.value = normalizedTraceId;
    }
    await Sentry.configureScope((scope) async {
      await scope.setTag('request_id', requestId);
      if (normalizedTraceId.isNotEmpty) {
        await scope.setTag('trace_id', normalizedTraceId);
      }
      if (statusCode != null) {
        scope.setContexts('http', <String, dynamic>{'status': statusCode});
      }
    });
  }

  static Future<void> recordHttpFailure({
    required String requestId,
    required String method,
    required Uri uri,
    required int statusCode,
    String? traceId,
    String? code,
  }) async {
    final normalizedTraceId = (traceId ?? '').trim();
    if (normalizedTraceId.isNotEmpty) {
      _lastTraceIdNotifier.value = normalizedTraceId;
    }
    await Sentry.configureScope((scope) async {
      await scope.setTag('request_id', requestId);
      if (normalizedTraceId.isNotEmpty) {
        await scope.setTag('trace_id', normalizedTraceId);
      }
    });
    await Sentry.addBreadcrumb(
      Breadcrumb(
        type: 'http',
        category: 'http.error',
        message: 'HTTP ${method.toUpperCase()} ${uri.path} failed',
        data: <String, dynamic>{
          'request_id': requestId,
          'trace_id': normalizedTraceId,
          'status_code': statusCode,
          'code': code ?? '',
        },
        level: SentryLevel.warning,
      ),
    );
  }

  static Future<void> setRuntimeContext({
    required String environment,
    required String appVersion,
    required String buildNumber,
    required String platform,
  }) async {
    await Sentry.configureScope((scope) async {
      await scope.setTag('environment', environment);
      await scope.setTag('app_version', appVersion);
      await scope.setTag('build_number', buildNumber);
      await scope.setTag('platform', platform);
      scope.setContexts('runtime', <String, dynamic>{'is_web': kIsWeb});
    });
  }

  static Future<void> setAuthenticatedUser({
    String? userId,
    String? role,
  }) async {
    final normalizedUserId = (userId ?? '').trim();
    final normalizedRole = (role ?? '').trim();
    await Sentry.configureScope((scope) async {
      if (normalizedUserId.isEmpty) {
        await scope.setUser(null);
      } else {
        await scope.setUser(SentryUser(id: scrubText(normalizedUserId)));
      }
      if (normalizedRole.isNotEmpty) {
        await scope.setTag('role', scrubText(normalizedRole));
      } else {
        await scope.removeTag('role');
      }
    });
  }

  static Future<void> clearAuthenticatedUser() async {
    await Sentry.configureScope((scope) async {
      await scope.setUser(null);
      await scope.removeTag('role');
    });
  }

  static Future<void> recordStartupStage({
    required String stage,
    String? detail,
    SentryLevel level = SentryLevel.info,
  }) {
    final sanitizedStage = scrubText(stage);
    final sanitizedDetail = _scrubNullable(detail);
    developer.log(
      sanitizedDetail == null || sanitizedDetail.isEmpty
          ? sanitizedStage
          : '$sanitizedStage | $sanitizedDetail',
      name: 'hailo.startup',
    );
    return Sentry.addBreadcrumb(
      Breadcrumb(
        type: 'navigation',
        category: 'startup',
        message: sanitizedStage,
        data: sanitizedDetail == null
            ? null
            : <String, dynamic>{'detail': sanitizedDetail},
        level: level,
      ),
    );
  }

  static FutureOr<SentryEvent?> beforeSend(SentryEvent event, Hint hint) {
    final message = event.message;
    if (message != null) {
      message.formatted = scrubText(message.formatted);
      message.template = _scrubNullable(message.template);
      message.params = message.params
          ?.map(_sanitizeDynamic)
          .toList(growable: false);
      event.message = message;
    }

    final breadcrumbs = event.breadcrumbs;
    if (breadcrumbs != null) {
      for (final breadcrumb in breadcrumbs) {
        if (breadcrumb.message != null) {
          breadcrumb.message = scrubText(breadcrumb.message!);
        }
        if (breadcrumb.data != null) {
          breadcrumb.data = _sanitizeDynamicMap(breadcrumb.data!);
        }
      }
      event.breadcrumbs = breadcrumbs;
    }

    event.user = _sanitizeUser(event.user);
    event.tags = _sanitizeStringMap(event.tags);
    return event;
  }

  @visibleForTesting
  static String scrubText(String value) {
    var masked = value;
    masked = masked.replaceAll(_emailPattern, '[redacted-email]');
    masked = masked.replaceAll(_phonePattern, '[redacted-phone]');
    return masked;
  }

  static String? _scrubNullable(String? value) {
    if (value == null) {
      return null;
    }
    return scrubText(value);
  }

  static Map<String, String>? _sanitizeStringMap(Map<String, String>? value) {
    if (value == null || value.isEmpty) {
      return value;
    }
    return value.map((key, item) => MapEntry(key, scrubText(item)));
  }

  static Map<String, dynamic>? _sanitizeDynamicMap(
    Map<String, dynamic>? value,
  ) {
    if (value == null || value.isEmpty) {
      return value;
    }
    return value.map((key, item) => MapEntry(key, _sanitizeDynamic(item)));
  }

  static dynamic _sanitizeDynamic(dynamic value) {
    if (value is String) {
      return scrubText(value);
    }
    if (value is List) {
      return value.map(_sanitizeDynamic).toList(growable: false);
    }
    if (value is Map<String, dynamic>) {
      return _sanitizeDynamicMap(value);
    }
    if (value is Map) {
      final mapped = <String, dynamic>{};
      for (final entry in value.entries) {
        mapped[entry.key.toString()] = _sanitizeDynamic(entry.value);
      }
      return mapped;
    }
    return value;
  }

  static SentryUser? _sanitizeUser(SentryUser? user) {
    if (user == null) {
      return null;
    }
    final cleanedId = user.id == null ? null : scrubText(user.id!);
    final cleanedUsername = user.username == null
        ? null
        : scrubText(user.username!);
    if ((cleanedId == null || cleanedId.isEmpty) &&
        (cleanedUsername == null || cleanedUsername.isEmpty)) {
      return null;
    }
    return SentryUser(
      id: cleanedId?.isEmpty == true ? null : cleanedId,
      username: cleanedUsername?.isEmpty == true ? null : cleanedUsername,
      name: user.name == null ? null : scrubText(user.name!),
      data: _sanitizeDynamicMap(user.data),
    );
  }
}
