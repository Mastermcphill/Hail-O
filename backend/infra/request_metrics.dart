class RequestMetrics {
  int _requestsTotal = 0;
  final Map<String, int> _statusFamilies = <String, int>{};
  final Map<String, int> _errorsByCode = <String, int>{};
  final Map<String, int> _marketplaceRequestsTotal =
      <String, int>{}; // key: route|method|status
  final Map<String, int> _marketplacePurchaseCreatesTotal =
      <String, int>{}; // key: status
  final Map<String, int> _marketplaceWebhookEventsTotal =
      <String, int>{}; // key: provider|action
  final Map<String, _LatencyStats> _marketplaceHandlerLatencyByRoute =
      <String, _LatencyStats>{}; // key: route
  final Map<String, _LatencyStats> _marketplaceDbLatencyByOp =
      <String, _LatencyStats>{}; // key: op
  int _marketplaceRateLimitedCount = 0;
  int _marketplaceWebhookVerificationFailures = 0;
  int _marketplacePaymentFailures = 0;

  void record({required int statusCode, String? errorCode}) {
    _recordBase(statusCode: statusCode, errorCode: errorCode);
  }

  void recordRequest({
    required int statusCode,
    required String method,
    required String path,
    required int latencyMs,
    String? errorCode,
  }) {
    _recordBase(statusCode: statusCode, errorCode: errorCode);

    if (!path.startsWith('marketplace/') && !path.startsWith('webhooks/')) {
      return;
    }

    final routeKey = '$path|${method.toUpperCase()}|$statusCode';
    _marketplaceRequestsTotal[routeKey] =
        (_marketplaceRequestsTotal[routeKey] ?? 0) + 1;

    final latencyStats = _marketplaceHandlerLatencyByRoute.putIfAbsent(
      path,
      () => _LatencyStats(),
    );
    latencyStats.record(latencyMs);

    if (path == 'marketplace/purchases' && method.toUpperCase() == 'POST') {
      final statusKey = statusCode >= 200 && statusCode < 300
          ? 'success'
          : 'error';
      _marketplacePurchaseCreatesTotal[statusKey] =
          (_marketplacePurchaseCreatesTotal[statusKey] ?? 0) + 1;
    }

    if ((errorCode ?? '').toUpperCase() == 'RATE_LIMITED') {
      _marketplaceRateLimitedCount += 1;
    }
  }

  void recordMarketplaceWebhookEvent({
    required String provider,
    required String action,
  }) {
    final key =
        '${provider.trim().toLowerCase()}|${action.trim().toLowerCase()}';
    _marketplaceWebhookEventsTotal[key] =
        (_marketplaceWebhookEventsTotal[key] ?? 0) + 1;
    if (action.trim().toLowerCase() == 'signature_invalid') {
      _marketplaceWebhookVerificationFailures += 1;
    }
  }

  void recordMarketplaceDbQueryLatency({
    required String op,
    required int latencyMs,
  }) {
    final stats = _marketplaceDbLatencyByOp.putIfAbsent(
      op,
      () => _LatencyStats(),
    );
    stats.record(latencyMs);
  }

  void recordMarketplacePaymentFailure() {
    _marketplacePaymentFailures += 1;
  }

  Map<String, Object?> snapshot() {
    final errorsTotal = _errorsByCode.values.fold<int>(
      0,
      (sum, value) => sum + value,
    );
    return <String, Object?>{
      'requests_total': _requestsTotal,
      'status_families': Map<String, int>.from(_statusFamilies),
      'errors_total': errorsTotal,
      'errors_by_code': Map<String, int>.from(_errorsByCode),
      'marketplace_requests_total': Map<String, int>.from(
        _marketplaceRequestsTotal,
      ),
      'marketplace_purchase_creates_total': Map<String, int>.from(
        _marketplacePurchaseCreatesTotal,
      ),
      'marketplace_webhook_events_total': Map<String, int>.from(
        _marketplaceWebhookEventsTotal,
      ),
      'marketplace_handler_latency_ms': _marketplaceHandlerLatencyByRoute.map(
        (key, value) => MapEntry(key, value.toMap()),
      ),
      'marketplace_db_query_latency_ms': _marketplaceDbLatencyByOp.map(
        (key, value) => MapEntry(key, value.toMap()),
      ),
      'marketplace_alert_signals': <String, int>{
        'rate_limited_count': _marketplaceRateLimitedCount,
        'webhook_verification_failures':
            _marketplaceWebhookVerificationFailures,
        'payment_failures': _marketplacePaymentFailures,
      },
    };
  }

  void _recordBase({required int statusCode, String? errorCode}) {
    _requestsTotal += 1;
    final family = '${statusCode ~/ 100}xx';
    _statusFamilies[family] = (_statusFamilies[family] ?? 0) + 1;
    if (errorCode != null && errorCode.isNotEmpty) {
      _errorsByCode[errorCode] = (_errorsByCode[errorCode] ?? 0) + 1;
    }
  }
}

class _LatencyStats {
  int _count = 0;
  int _totalMs = 0;
  int _maxMs = 0;

  void record(int latencyMs) {
    final safeLatency = latencyMs < 0 ? 0 : latencyMs;
    _count += 1;
    _totalMs += safeLatency;
    if (safeLatency > _maxMs) {
      _maxMs = safeLatency;
    }
  }

  Map<String, Object?> toMap() {
    final avg = _count == 0 ? 0 : (_totalMs / _count);
    return <String, Object?>{'count': _count, 'avg_ms': avg, 'max_ms': _maxMs};
  }
}
