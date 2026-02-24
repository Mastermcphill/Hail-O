import 'dart:math';

import 'api_error.dart';
import 'api_errors.dart';

class ApiPolicy {
  ApiPolicy({
    required this.method,
    required this.hasIdempotencyKey,
    this.requestTimeout = const Duration(seconds: 25),
    this.maxRetryAttempts = 1,
    this.baseBackoff = const Duration(milliseconds: 400),
    this.maxBackoff = const Duration(seconds: 2),
    this.maxJitterMs = 250,
  });

  final String method;
  final bool hasIdempotencyKey;
  final Duration requestTimeout;
  final int maxRetryAttempts;
  final Duration baseBackoff;
  final Duration maxBackoff;
  final int maxJitterMs;

  static ApiPolicy forRequest({
    required String method,
    bool hasIdempotencyKey = false,
  }) {
    return ApiPolicy(
      method: method.trim().toUpperCase(),
      hasIdempotencyKey: hasIdempotencyKey,
    );
  }

  bool canRetry(int attempt) {
    return attempt < maxRetryAttempts;
  }

  bool shouldRetryApiException(ApiException error, int attempt) {
    if (!canRetry(attempt)) {
      return false;
    }
    if (_isMethodRetryableForApiStatus(method, hasIdempotencyKey)) {
      final status = error.statusCode;
      return status == 502 || status == 503 || status == 504;
    }
    return false;
  }

  bool shouldRetryTransportError(ApiErrorKind kind, int attempt) {
    if (!canRetry(attempt)) {
      return false;
    }
    if (!_isMethodRetryableForTransport(method, hasIdempotencyKey)) {
      return false;
    }
    return kind == ApiErrorKind.timeout || kind == ApiErrorKind.network;
  }

  Duration retryDelay(int attempt) {
    final exponent = 1 << attempt;
    final rawMs = baseBackoff.inMilliseconds * exponent;
    final cappedMs = min(rawMs, maxBackoff.inMilliseconds);
    final jitter = Random().nextInt(maxJitterMs + 1);
    return Duration(milliseconds: cappedMs + jitter);
  }
}

bool _isMethodRetryableForApiStatus(String method, bool hasIdempotencyKey) {
  if (method == 'GET' || method == 'HEAD') {
    return true;
  }
  if (method == 'POST') {
    return hasIdempotencyKey;
  }
  return false;
}

bool _isMethodRetryableForTransport(String method, bool hasIdempotencyKey) {
  return _isMethodRetryableForApiStatus(method, hasIdempotencyKey);
}
