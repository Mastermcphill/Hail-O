class ApiException implements Exception {
  const ApiException({
    required this.statusCode,
    required this.code,
    required this.message,
    this.traceId,
    this.rawBody,
  });

  final int statusCode;
  final String code;
  final String message;
  final String? traceId;
  final String? rawBody;

  @override
  String toString() {
    final trace = traceId == null ? '' : ' trace_id=$traceId';
    return 'ApiException(status=$statusCode code=$code$message$trace)';
  }
}
