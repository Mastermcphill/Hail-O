class RequestMetrics {
  int _requestsTotal = 0;
  final Map<String, int> _statusFamilies = <String, int>{};
  final Map<String, int> _errorsByCode = <String, int>{};

  void record({required int statusCode, String? errorCode}) {
    _requestsTotal += 1;
    final family = '${statusCode ~/ 100}xx';
    _statusFamilies[family] = (_statusFamilies[family] ?? 0) + 1;
    if (errorCode != null && errorCode.isNotEmpty) {
      _errorsByCode[errorCode] = (_errorsByCode[errorCode] ?? 0) + 1;
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
    };
  }
}
