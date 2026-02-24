import 'package:sentry/sentry.dart';
import 'package:shelf/shelf.dart';

import 'request_context.dart';

class BackendSentryObservability {
  BackendSentryObservability._();

  static bool _enabled = false;
  static bool get isEnabled => _enabled;

  static Future<void> configure({
    required String dsn,
    required String environment,
    required String release,
  }) async {
    if (dsn.trim().isEmpty) {
      _enabled = false;
      return;
    }
    await Sentry.init((options) {
      options.dsn = dsn.trim();
      options.environment = environment;
      options.release = release;
      options.sendDefaultPii = false;
      options.tracesSampleRate = 0.2;
    });
    _enabled = true;
  }

  static Future<void> captureException(
    Object error,
    StackTrace stackTrace, {
    Request? request,
    String? source,
  }) async {
    if (!_enabled) {
      return;
    }
    await Sentry.captureException(
      error,
      stackTrace: stackTrace,
      withScope: (scope) {
        if (source != null && source.trim().isNotEmpty) {
          scope.setTag('error_source', source.trim());
        }
        if (request != null) {
          final context = request.requestContext;
          scope.setTag('request_id', context.traceId);
          scope.setTag('method', request.method.toUpperCase());
          scope.setTag('route', request.url.path);
          scope.setContexts('request', <String, Object?>{
            'trace_id': context.traceId,
            'path': request.url.path,
            'method': request.method.toUpperCase(),
            'user_id': context.userId,
            'role': context.role,
          });
        }
      },
    );
  }
}
