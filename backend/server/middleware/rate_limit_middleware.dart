import 'package:shelf/shelf.dart';

import '../../infra/request_context.dart';
import '../http_utils.dart';

typedef NowProvider = DateTime Function();

class _CounterBucket {
  _CounterBucket({required this.windowStartUtc, required this.count});

  DateTime windowStartUtc;
  int count;
}

Middleware rateLimitMiddleware({
  Duration window = const Duration(minutes: 1),
  int maxRequestsPerIp = 60,
  int maxRequestsPerUser = 120,
  Set<String> exemptPaths = const <String>{'health', 'api/healthz'},
  NowProvider? nowProvider,
}) {
  final ipBuckets = <String, _CounterBucket>{};
  final userBuckets = <String, _CounterBucket>{};
  final now = nowProvider ?? () => DateTime.now().toUtc();

  bool consume(
    Map<String, _CounterBucket> buckets,
    String key,
    DateTime currentUtc,
    int maxRequests,
  ) {
    final bucket = buckets.putIfAbsent(
      key,
      () => _CounterBucket(windowStartUtc: currentUtc, count: 0),
    );
    if (currentUtc.difference(bucket.windowStartUtc) >= window) {
      bucket.windowStartUtc = currentUtc;
      bucket.count = 0;
    }
    if (bucket.count >= maxRequests) {
      return false;
    }
    bucket.count += 1;
    return true;
  }

  return (Handler innerHandler) {
    return (Request request) {
      final path = request.url.path;
      if (exemptPaths.contains(path)) {
        return innerHandler(request);
      }

      final currentUtc = now();
      final ipKey = _extractClientIp(request);
      if (!consume(ipBuckets, ipKey, currentUtc, maxRequestsPerIp)) {
        return Future<Response>.value(
          jsonErrorResponse(
            request,
            429,
            code: 'rate_limited',
            message: 'Too many requests for this IP',
            headers: <String, String>{'retry-after': '${window.inSeconds}'},
          ),
        );
      }

      final userId = request.requestContext.userId?.trim() ?? '';
      if (userId.isNotEmpty &&
          !consume(userBuckets, userId, currentUtc, maxRequestsPerUser)) {
        return Future<Response>.value(
          jsonErrorResponse(
            request,
            429,
            code: 'rate_limited',
            message: 'Too many requests for this user',
            headers: <String, String>{'retry-after': '${window.inSeconds}'},
          ),
        );
      }

      return innerHandler(request);
    };
  };
}

String _extractClientIp(Request request) {
  final forwarded = request.headers['x-forwarded-for']?.trim() ?? '';
  if (forwarded.isNotEmpty) {
    return forwarded.split(',').first.trim();
  }
  final realIp = request.headers['x-real-ip']?.trim() ?? '';
  if (realIp.isNotEmpty) {
    return realIp;
  }
  return 'unknown';
}
