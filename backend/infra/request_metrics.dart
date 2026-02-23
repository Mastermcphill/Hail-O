class RequestMetrics {
  int _requestsTotal = 0;
  final Map<String, int> _statusFamilies = <String, int>{};
  final Map<String, int> _errorsByCode = <String, int>{};
  final Map<String, int> _marketplaceRequestsTotal = <String, int>{};
  final Map<String, int> _marketplacePurchaseCreatesTotal = <String, int>{};
  final Map<String, int> _marketplaceWebhookEventsTotal = <String, int>{};
  final Map<String, int> _marketplaceHandlerLatencyMs = <String, int>{};
  int _marketplaceReconciliationsTotal = 0;
  int _marketplaceReconciliationDriftDetected = 0;
  int _marketplaceReconciliationApplied = 0;
  int _rateLimitedTotal = 0;
  int _marketplaceWebhookVerificationFailures = 0;
  int _marketplacePaymentFailures = 0;

  void record({required int statusCode, String? errorCode}) {
    _requestsTotal += 1;
    final family = '${statusCode ~/ 100}xx';
    _statusFamilies[family] = (_statusFamilies[family] ?? 0) + 1;
    if (errorCode != null && errorCode.isNotEmpty) {
      _errorsByCode[errorCode] = (_errorsByCode[errorCode] ?? 0) + 1;
      if (errorCode.trim().toLowerCase() == 'rate_limited') {
        _rateLimitedTotal += 1;
      }
    }
  }

  void recordMarketplaceRequest({
    required String route,
    required String method,
    required int statusCode,
    required int latencyMs,
  }) {
    final key = '$route|${method.toUpperCase()}|$statusCode';
    _marketplaceRequestsTotal[key] = (_marketplaceRequestsTotal[key] ?? 0) + 1;
    final latencyKey = route;
    _marketplaceHandlerLatencyMs[latencyKey] =
        (_marketplaceHandlerLatencyMs[latencyKey] ?? 0) + latencyMs;
  }

  void recordMarketplacePurchaseCreate({required String status}) {
    final key = status.trim().toLowerCase();
    _marketplacePurchaseCreatesTotal[key] =
        (_marketplacePurchaseCreatesTotal[key] ?? 0) + 1;
  }

  void recordMarketplaceWebhookEvent({
    required String provider,
    required String action,
  }) {
    final key =
        '${provider.trim().toLowerCase()}|${action.trim().toLowerCase()}';
    _marketplaceWebhookEventsTotal[key] =
        (_marketplaceWebhookEventsTotal[key] ?? 0) + 1;
  }

  void recordMarketplaceWebhookVerificationFailure() {
    _marketplaceWebhookVerificationFailures += 1;
  }

  void recordMarketplacePaymentFailure() {
    _marketplacePaymentFailures += 1;
  }

  void recordMarketplaceReconciliation({
    required bool driftDetected,
    required bool applied,
    required bool dryRun,
  }) {
    _marketplaceReconciliationsTotal += 1;
    if (driftDetected) {
      _marketplaceReconciliationDriftDetected += 1;
    }
    if (applied && !dryRun) {
      _marketplaceReconciliationApplied += 1;
    }
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
      'marketplace_handler_latency_ms': Map<String, int>.from(
        _marketplaceHandlerLatencyMs,
      ),
      'marketplace_reconciliations_total': _marketplaceReconciliationsTotal,
      'marketplace_reconciliation_drift_detected':
          _marketplaceReconciliationDriftDetected,
      'marketplace_reconciliation_applied': _marketplaceReconciliationApplied,
      'alerts': <String, int>{
        'rate_limited_total': _rateLimitedTotal,
        'webhook_verification_failures':
            _marketplaceWebhookVerificationFailures,
        'payment_failures': _marketplacePaymentFailures,
      },
    };
  }
}
