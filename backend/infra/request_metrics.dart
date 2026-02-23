class RequestMetrics {
  int _requestsTotal = 0;
  final Map<String, int> _statusFamilies = <String, int>{};
  final Map<String, int> _errorsByCode = <String, int>{};

  final Map<String, int> _marketplaceRequestsTotal = <String, int>{};
  final Map<String, int> _marketplacePurchaseCreatesTotal = <String, int>{};
  final Map<String, int> _marketplaceWebhookEventsTotal = <String, int>{};
  final Map<String, Map<String, num>> _marketplaceHandlerLatencyByRoute =
      <String, Map<String, num>>{};
  final Map<String, Map<String, num>> _marketplaceDbLatencyByOp =
      <String, Map<String, num>>{};
  final Map<String, int> _marketplaceAlertSignals = <String, int>{};

  final Map<String, int> _couponApplyTotal = <String, int>{};
  final Map<String, int> _referralApplyTotal = <String, int>{};
  final Map<String, int> _invoicesCreatedTotal = <String, int>{};
  final Map<String, int> _dunningAttemptsTotal = <String, int>{};
  final Map<String, int> _riskStateTotal = <String, int>{};
  final Map<String, int> _commsSentTotal = <String, int>{};
  int _creditsAppliedTotal = 0;
  int _dunningRecoveredTotal = 0;

  void record({required int statusCode, String? errorCode}) {
    _recordCore(statusCode: statusCode, errorCode: errorCode);
  }

  void recordRequest({
    required int statusCode,
    String? method,
    String? path,
    int? latencyMs,
    String? errorCode,
  }) {
    _recordCore(statusCode: statusCode, errorCode: errorCode);
    final normalizedMethod = (method ?? '').trim().toUpperCase();
    final normalizedPath = (path ?? '').trim();
    if (normalizedPath.startsWith('marketplace')) {
      final routeKey = normalizedMethod.isEmpty
          ? normalizedPath
          : '$normalizedMethod $normalizedPath';
      _increment(_marketplaceRequestsTotal, routeKey);
      if (normalizedMethod == 'POST' &&
          normalizedPath == 'marketplace/purchases') {
        _increment(
          _marketplacePurchaseCreatesTotal,
          statusCode >= 400 ? 'failure' : 'success',
        );
      }
      if (latencyMs != null) {
        _recordLatency(_marketplaceHandlerLatencyByRoute, normalizedPath, latencyMs);
      }
    }
  }

  void recordMarketplaceRequest({
    required String route,
    required String method,
    required int statusCode,
    required int latencyMs,
    String? errorCode,
  }) {
    final normalizedRoute = route.trim().replaceFirst(RegExp(r'^/'), '');
    recordRequest(
      statusCode: statusCode,
      method: method,
      path: normalizedRoute,
      latencyMs: latencyMs,
      errorCode: errorCode,
    );
  }

  void recordMarketplaceWebhookEvent({
    required String provider,
    required String action,
  }) {
    final normalizedProvider = provider.trim().isEmpty
        ? 'unknown'
        : provider.trim().toLowerCase();
    final normalizedAction = action.trim().isEmpty
        ? 'unknown'
        : action.trim().toLowerCase();
    _increment(
      _marketplaceWebhookEventsTotal,
      '$normalizedProvider:$normalizedAction',
    );
  }

  void recordMarketplaceDbQueryLatency({
    required String op,
    required int latencyMs,
  }) {
    final normalizedOp = op.trim().isEmpty ? 'unknown' : op.trim().toLowerCase();
    _recordLatency(_marketplaceDbLatencyByOp, normalizedOp, latencyMs);
  }

  void recordMarketplacePaymentFailure() {
    _increment(_marketplaceAlertSignals, 'payment_failure');
  }

  void recordMarketplaceWebhookVerificationFailure() {
    _increment(_marketplaceAlertSignals, 'webhook_signature_invalid');
  }

  void recordCouponApply({required String result}) {
    final normalized = result.trim().isEmpty ? 'unknown' : result.trim().toLowerCase();
    _increment(_couponApplyTotal, normalized);
  }

  void recordReferralApply({required String result}) {
    final normalized = result.trim().isEmpty ? 'unknown' : result.trim().toLowerCase();
    _increment(_referralApplyTotal, normalized);
  }

  void recordInvoiceCreated({required String status}) {
    final normalized = status.trim().isEmpty ? 'unknown' : status.trim().toLowerCase();
    _increment(_invoicesCreatedTotal, normalized);
    if (normalized == 'paid') {
      _increment(_invoicesCreatedTotal, 'paid_total');
    } else if (normalized == 'failed') {
      _increment(_invoicesCreatedTotal, 'failed_total');
    }
  }

  void recordDunningAttempt({required String outcome}) {
    final normalized = outcome.trim().isEmpty
        ? 'unknown'
        : outcome.trim().toLowerCase();
    _increment(_dunningAttemptsTotal, normalized);
    if (normalized == 'success') {
      _dunningRecoveredTotal += 1;
    }
  }

  void recordRiskState({required String state}) {
    final normalized = state.trim().isEmpty ? 'unknown' : state.trim().toLowerCase();
    _increment(_riskStateTotal, normalized);
  }

  void recordCommsSent({required String channel, required String template}) {
    final normalizedChannel = channel.trim().isEmpty
        ? 'unknown'
        : channel.trim().toLowerCase();
    final normalizedTemplate = template.trim().isEmpty
        ? 'unknown'
        : template.trim().toLowerCase();
    _increment(_commsSentTotal, '$normalizedChannel:$normalizedTemplate');
  }

  void recordCreditsApplied({required int amountMinor}) {
    final normalized = amountMinor < 0 ? 0 : amountMinor;
    _creditsAppliedTotal += normalized;
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
      'marketplace_handler_latency_ms': _latencySnapshot(
        _marketplaceHandlerLatencyByRoute,
      ),
      'marketplace_db_query_latency_ms': _latencySnapshot(
        _marketplaceDbLatencyByOp,
      ),
      'marketplace_alert_signals': Map<String, int>.from(_marketplaceAlertSignals),
      'coupon_apply_total': Map<String, int>.from(_couponApplyTotal),
      'referral_apply_total': Map<String, int>.from(_referralApplyTotal),
      'invoices_created_total': _sumMap(_invoicesCreatedTotal),
      'invoices_paid_total': _invoicesCreatedTotal['paid_total'] ?? 0,
      'invoices_failed_total': _invoicesCreatedTotal['failed_total'] ?? 0,
      'dunning_attempts_total': Map<String, int>.from(_dunningAttemptsTotal),
      'dunning_recovered_total': _dunningRecoveredTotal,
      'risk_state_total': Map<String, int>.from(_riskStateTotal),
      'credits_applied_total': _creditsAppliedTotal,
      'comms_sent_total': Map<String, int>.from(_commsSentTotal),
    };
  }

  void _recordCore({required int statusCode, String? errorCode}) {
    _requestsTotal += 1;
    final family = '${statusCode ~/ 100}xx';
    _statusFamilies[family] = (_statusFamilies[family] ?? 0) + 1;
    final normalizedError = (errorCode ?? '').trim();
    if (normalizedError.isNotEmpty) {
      _errorsByCode[normalizedError] = (_errorsByCode[normalizedError] ?? 0) + 1;
    }
  }

  void _recordLatency(
    Map<String, Map<String, num>> bucket,
    String key,
    int latencyMs,
  ) {
    final normalizedLatency = latencyMs < 0 ? 0 : latencyMs;
    final aggregate = bucket.putIfAbsent(
      key,
      () => <String, num>{
        'count': 0,
        'sum': 0,
        'min': normalizedLatency,
        'max': normalizedLatency,
      },
    );
    final count = (aggregate['count'] as num).toInt() + 1;
    final sum = (aggregate['sum'] as num).toInt() + normalizedLatency;
    final min = (aggregate['min'] as num).toInt();
    final max = (aggregate['max'] as num).toInt();
    aggregate['count'] = count;
    aggregate['sum'] = sum;
    aggregate['min'] = normalizedLatency < min ? normalizedLatency : min;
    aggregate['max'] = normalizedLatency > max ? normalizedLatency : max;
  }

  Map<String, Object?> _latencySnapshot(Map<String, Map<String, num>> source) {
    return <String, Object?>{
      for (final entry in source.entries)
        entry.key: <String, num>{
          'count': (entry.value['count'] as num).toInt(),
          'avg': (entry.value['count'] as num).toInt() == 0
              ? 0
              : ((entry.value['sum'] as num) / (entry.value['count'] as num)),
          'min': (entry.value['min'] as num).toInt(),
          'max': (entry.value['max'] as num).toInt(),
        },
    };
  }

  int _sumMap(Map<String, int> values) {
    var sum = 0;
    for (final value in values.values) {
      sum += value;
    }
    return sum;
  }

  void _increment(Map<String, int> bucket, String key, [int by = 1]) {
    bucket[key] = (bucket[key] ?? 0) + by;
  }
}
