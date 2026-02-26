import 'dart:io';

import 'package:shelf/shelf.dart';

import '../../infra/redis_client.dart';
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
  int maxAuthRequestsPerIp = 20,
  int maxAuthRequestsPerUser = 40,
  int maxMarketplaceReadRequestsPerIp = 120,
  int maxMarketplaceReadRequestsPerUser = 240,
  int maxMarketplaceWriteRequestsPerIp = 40,
  int maxMarketplaceWriteRequestsPerUser = 80,
  int maxWebhookRequestsPerIp = 300,
  int? maxWebhookRequestsPerUser,
  int maxAdminRequestsPerIp = 30,
  int maxAdminRequestsPerUser = 60,
  bool trustProxyHeaders = true,
  Set<String> exemptPaths = const <String>{'health', 'healthz', 'ready'},
  RedisQueueClient? redisClient,
  void Function(String line)? warningSink,
  NowProvider? nowProvider,
}) {
  final ipBuckets = <String, _CounterBucket>{};
  final userBuckets = <String, _CounterBucket>{};
  final now = nowProvider ?? () => DateTime.now().toUtc();
  final webhookRequestsPerUser =
      maxWebhookRequestsPerUser ?? maxRequestsPerUser;

  bool consumeInMemory(
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

  Future<bool> consumeRedis(String key, int maxRequests) async {
    final client = redisClient;
    if (client == null || maxRequests <= 0) {
      return true;
    }
    try {
      final count = await client.incrementWithWindow(key, window: window);
      return count <= maxRequests;
    } catch (error) {
      warningSink?.call('WARN: redis rate limit counter unavailable: $error');
      return true;
    }
  }

  return (Handler innerHandler) {
    return (Request request) async {
      final path = _canonicalPath(request.url.path);
      if (exemptPaths.contains(path)) {
        return innerHandler(request);
      }

      final currentUtc = now();
      final userId = request.requestContext.userId?.trim() ?? '';
      final ipKey = _extractClientIp(
        request,
        trustProxyHeaders: trustProxyHeaders,
      );
      final method = request.method.toUpperCase();
      final isAuthPath = path.startsWith('auth/');
      final isMarketplacePath = path.startsWith('marketplace/');
      final isOrgPath = path == 'orgs' || path.startsWith('orgs/');
      final isMarketplaceOfferRead =
          isMarketplacePath &&
          method == 'GET' &&
          (path == 'marketplace/offers' ||
              path.startsWith('marketplace/offers/'));
      final isWebhookPath = path.startsWith('webhooks/');
      final isAdminPath = path == 'admin' || path.startsWith('admin/');

      int ipLimit;
      int userLimit;
      String bucketScope;
      if (isWebhookPath) {
        ipLimit = maxWebhookRequestsPerIp;
        userLimit = webhookRequestsPerUser;
        bucketScope = 'webhook';
      } else if (isAdminPath) {
        ipLimit = maxAdminRequestsPerIp;
        userLimit = maxAdminRequestsPerUser;
        bucketScope = 'admin';
      } else if (isMarketplacePath || isOrgPath) {
        ipLimit = isMarketplaceOfferRead
            ? maxMarketplaceReadRequestsPerIp
            : maxMarketplaceWriteRequestsPerIp;
        userLimit = isMarketplaceOfferRead
            ? maxMarketplaceReadRequestsPerUser
            : maxMarketplaceWriteRequestsPerUser;
        bucketScope = isMarketplaceOfferRead
            ? 'marketplace_read'
            : 'marketplace_write';
      } else {
        ipLimit = isAuthPath ? maxAuthRequestsPerIp : maxRequestsPerIp;
        userLimit = isAuthPath ? maxAuthRequestsPerUser : maxRequestsPerUser;
        bucketScope = isAuthPath ? 'auth' : 'general';
      }
      final ipBucketKey = 'ratelimit:$bucketScope:ip:$ipKey';
      final userBucketKey = 'ratelimit:$bucketScope:user:$userId';
      final ipAllowed = redisClient == null
          ? consumeInMemory(ipBuckets, ipBucketKey, currentUtc, ipLimit)
          : await consumeRedis(ipBucketKey, ipLimit);
      if (!ipAllowed) {
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

      if (userLimit > 0 &&
          userId.isNotEmpty &&
          !(redisClient == null
              ? consumeInMemory(
                  userBuckets,
                  userBucketKey,
                  currentUtc,
                  userLimit,
                )
              : await consumeRedis(userBucketKey, userLimit))) {
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

String _canonicalPath(String path) {
  final trimmed = path.trim();
  if (trimmed == 'api') {
    return '';
  }
  if (trimmed.startsWith('api/')) {
    return trimmed.substring(4);
  }
  return trimmed;
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
