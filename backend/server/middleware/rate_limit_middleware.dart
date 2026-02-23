import 'dart:io';

import 'package:shelf/shelf.dart';
import 'package:uuid/uuid.dart';

import '../../infra/request_context.dart';
import '../http_utils.dart';

typedef NowProvider = DateTime Function();

class _CounterBucket {
  _CounterBucket({required this.windowStartUtc, required this.count});

  DateTime windowStartUtc;
  int count;
}

class _RateLimitRule {
  const _RateLimitRule({
    required this.maxRequestsPerIp,
    required this.maxRequestsPerUser,
    required this.bucket,
  });

  final int maxRequestsPerIp;
  final int maxRequestsPerUser;
  final String bucket;
}

Middleware rateLimitMiddleware({
  Duration window = const Duration(minutes: 1),
  int maxRequestsPerIp = 60,
  int maxRequestsPerUser = 120,
  int maxAuthRequestsPerIp = 20,
  int maxAuthRequestsPerUser = 40,
  int maxMarketplaceReadRequestsPerIp = 180,
  int maxMarketplaceReadRequestsPerUser = 360,
  int maxMarketplaceWriteRequestsPerIp = 30,
  int maxMarketplaceWriteRequestsPerUser = 60,
  int maxWebhookRequestsPerIp = 600,
  int maxWebhookRequestsPerUser = 1200,
  bool trustProxyHeaders = true,
  Set<String> exemptPaths = const <String>{'health', 'api/healthz'},
  NowProvider? nowProvider,
  Uuid? uuid,
}) {
  final ipBuckets = <String, _CounterBucket>{};
  final userBuckets = <String, _CounterBucket>{};
  final now = nowProvider ?? () => DateTime.now().toUtc();
  final traceUuid = uuid ?? const Uuid();

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

  _RateLimitRule ruleFor(Request request) {
    final path = request.url.path;
    final method = request.method.toUpperCase();

    if (path.startsWith('webhooks/')) {
      return _RateLimitRule(
        maxRequestsPerIp: maxWebhookRequestsPerIp,
        maxRequestsPerUser: maxWebhookRequestsPerUser,
        bucket: 'webhooks',
      );
    }

    if (path.startsWith('marketplace/offers')) {
      return _RateLimitRule(
        maxRequestsPerIp: maxMarketplaceReadRequestsPerIp,
        maxRequestsPerUser: maxMarketplaceReadRequestsPerUser,
        bucket: 'marketplace_read',
      );
    }

    if (path.startsWith('marketplace/purchases')) {
      final isWriteMethod =
          method == 'POST' ||
          method == 'PATCH' ||
          method == 'PUT' ||
          method == 'DELETE';
      return isWriteMethod
          ? _RateLimitRule(
              maxRequestsPerIp: maxMarketplaceWriteRequestsPerIp,
              maxRequestsPerUser: maxMarketplaceWriteRequestsPerUser,
              bucket: 'marketplace_write',
            )
          : _RateLimitRule(
              maxRequestsPerIp: maxMarketplaceReadRequestsPerIp,
              maxRequestsPerUser: maxMarketplaceReadRequestsPerUser,
              bucket: 'marketplace_read',
            );
    }

    if (path.startsWith('auth/')) {
      return _RateLimitRule(
        maxRequestsPerIp: maxAuthRequestsPerIp,
        maxRequestsPerUser: maxAuthRequestsPerUser,
        bucket: 'auth',
      );
    }

    return _RateLimitRule(
      maxRequestsPerIp: maxRequestsPerIp,
      maxRequestsPerUser: maxRequestsPerUser,
      bucket: 'default',
    );
  }

  return (Handler innerHandler) {
    return (Request request) {
      final path = request.url.path;
      if (exemptPaths.contains(path)) {
        return innerHandler(request);
      }

      final currentUtc = now();
      final userId = request.requestContext.userId?.trim() ?? '';
      final isAuthenticated = userId.isNotEmpty;
      final ipKey = _extractClientIp(
        request,
        trustProxyHeaders: trustProxyHeaders,
      );
      final rule = ruleFor(request);
      final bucketKeyPrefix = '${rule.bucket}::';

      if (isAuthenticated) {
        final key = '$bucketKeyPrefix$userId';
        if (!consume(userBuckets, key, currentUtc, rule.maxRequestsPerUser)) {
          return Future<Response>.value(
            _rateLimitedResponse(
              request,
              traceUuid,
              message: 'Too many requests for this user',
              retryAfterSeconds: window.inSeconds,
            ),
          );
        }
      } else {
        final key = '$bucketKeyPrefix$ipKey';
        if (!consume(ipBuckets, key, currentUtc, rule.maxRequestsPerIp)) {
          return Future<Response>.value(
            _rateLimitedResponse(
              request,
              traceUuid,
              message: 'Too many requests for this IP',
              retryAfterSeconds: window.inSeconds,
            ),
          );
        }
      }

      return innerHandler(request);
    };
  };
}

Response _rateLimitedResponse(
  Request request,
  Uuid uuid, {
  required String message,
  required int retryAfterSeconds,
}) {
  final traceId = _resolveTraceId(request, uuid);
  return jsonResponse(
    429,
    <String, Object?>{
      'ok': false,
      'trace_id': traceId,
      'error_code': 'RATE_LIMITED',
      'code': 'rate_limited',
      'message': message,
    },
    headers: <String, String>{
      'retry-after': '$retryAfterSeconds',
      'x-error-code': 'RATE_LIMITED',
    },
  );
}

String _resolveTraceId(Request request, Uuid uuid) {
  final traceFromContext = request.requestContext.traceId.trim();
  if (traceFromContext.isNotEmpty && traceFromContext != 'trace-unset') {
    return traceFromContext;
  }
  final traceFromHeader = (request.headers['x-trace-id'] ?? '').trim();
  if (traceFromHeader.isNotEmpty) {
    return traceFromHeader;
  }
  return uuid.v4();
}

String _extractClientIp(Request request, {required bool trustProxyHeaders}) {
  if (trustProxyHeaders) {
    final forwarded = request.headers['x-forwarded-for']?.trim() ?? '';
    if (forwarded.isNotEmpty) {
      return forwarded.split(',').first.trim();
    }
    final realIp = request.headers['x-real-ip']?.trim() ?? '';
    if (realIp.isNotEmpty) {
      return realIp;
    }
  }

  final connectionInfo = request.context['shelf.io.connection_info'];
  if (connectionInfo is HttpConnectionInfo) {
    final address = connectionInfo.remoteAddress.address.trim();
    if (address.isNotEmpty) {
      return address;
    }
  }
  return 'unknown';
}
