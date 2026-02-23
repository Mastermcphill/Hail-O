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
  final Map<String, int> _marketplaceReconciliationsTotal =
      <String, int>{}; // key: dry_run|drift|applied
  int _marketplaceRateLimitedCount = 0;
  int _marketplaceWebhookVerificationFailures = 0;
  int _marketplacePaymentFailures = 0;
  int _marketplaceReconciliationDriftDetected = 0;
  int _marketplaceReconciliationApplied = 0;
  int _invoicesCreatedTotal = 0;
  int _invoicesPaidTotal = 0;
  int _invoicesFailedTotal = 0;
  final Map<String, int> _dunningAttemptsTotal = <String, int>{};
  int _dunningRecoveredTotal = 0;
  final Map<String, int> _riskStateTotal = <String, int>{};
  final Map<String, int> _couponApplyTotal = <String, int>{};
  final Map<String, int> _referralApplyTotal = <String, int>{};
  int _creditsAppliedTotal = 0;
  final Map<String, int> _commsSentTotal = <String, int>{};

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

  void recordMarketplaceReconciliation({
    required bool driftDetected,
    required bool applied,
    required bool dryRun,
  }) {
    final key =
        '${dryRun ? 'dry_run' : 'execute'}|${driftDetected ? 'drift' : 'clean'}|${applied ? 'applied' : 'not_applied'}';
    _marketplaceReconciliationsTotal[key] =
        (_marketplaceReconciliationsTotal[key] ?? 0) + 1;
    if (driftDetected) {
      _marketplaceReconciliationDriftDetected += 1;
    }
    if (applied) {
      _marketplaceReconciliationApplied += 1;
    }
  }

  void recordInvoiceCreated({required String status}) {
    _invoicesCreatedTotal += 1;
    final normalized = status.trim().toLowerCase();
    if (normalized == 'paid') {
      _invoicesPaidTotal += 1;
    } else if (normalized == 'failed' || normalized == 'open') {
      _invoicesFailedTotal += 1;
    }
  }

  void recordDunningAttempt({required String outcome}) {
    final key = outcome.trim().toLowerCase();
    _dunningAttemptsTotal[key] = (_dunningAttemptsTotal[key] ?? 0) + 1;
    if (key == 'success') {
      _dunningRecoveredTotal += 1;
    }
  }

  void recordRiskState({required String state}) {
    final key = state.trim().toLowerCase();
    _riskStateTotal[key] = (_riskStateTotal[key] ?? 0) + 1;
  }

  void recordCouponApply({required String result}) {
    final key = result.trim().toLowerCase();
    _couponApplyTotal[key] = (_couponApplyTotal[key] ?? 0) + 1;
  }

  void recordReferralApply({required String result}) {
    final key = result.trim().toLowerCase();
    _referralApplyTotal[key] = (_referralApplyTotal[key] ?? 0) + 1;
  }

  void recordCreditsApplied({required int amountMinor}) {
    if (amountMinor > 0) {
      _creditsAppliedTotal += amountMinor;
    }
  }

  void recordCommsSent({required String channel, required String template}) {
    final key = '${channel.trim().toLowerCase()}|${template.trim().toLowerCase()}';
    _commsSentTotal[key] = (_commsSentTotal[key] ?? 0) + 1;
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
      'marketplace_reconciliations_total': Map<String, int>.from(
        _marketplaceReconciliationsTotal,
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
        'reconciliation_drift_detected':
            _marketplaceReconciliationDriftDetected,
        'reconciliation_applied': _marketplaceReconciliationApplied,
      },
      'invoices_created_total': _invoicesCreatedTotal,
      'invoices_paid_total': _invoicesPaidTotal,
      'invoices_failed_total': _invoicesFailedTotal,
      'dunning_attempts_total': Map<String, int>.from(_dunningAttemptsTotal),
      'dunning_recovered_total': _dunningRecoveredTotal,
      'risk_state_total': Map<String, int>.from(_riskStateTotal),
      'coupon_apply_total': Map<String, int>.from(_couponApplyTotal),
      'referral_apply_total': Map<String, int>.from(_referralApplyTotal),
      'credits_applied_total': _creditsAppliedTotal,
      'comms_sent_total': Map<String, int>.from(_commsSentTotal),
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
