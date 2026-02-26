import 'dart:math';

import 'api_error.dart';
import 'api_errors.dart';

class ApiPolicy {
  ApiPolicy({
    required this.method,
    required this.hasIdempotencyKey,
    this.requestTimeout = const Duration(seconds: 12),
    this.maxRetryAttempts = 2,
    this.baseBackoff = const Duration(milliseconds: 350),
    this.maxBackoff = const Duration(seconds: 3),
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
    if (error.statusCode == 400 ||
        error.statusCode == 401 ||
        error.statusCode == 403) {
      return false;
    }
    if (_isMethodRetryableForApiStatus(method, hasIdempotencyKey)) {
      final status = error.statusCode;
      return status == 502 || status == 503;
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
  if (method == 'GET' ||
      method == 'HEAD' ||
      method == 'PUT' ||
      method == 'PATCH' ||
      method == 'DELETE' ||
      method == 'OPTIONS') {
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
