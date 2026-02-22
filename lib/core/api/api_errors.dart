class ApiException implements Exception {
  ApiException({
    required this.statusCode,
    required this.message,
    this.code,
    this.traceId,
    this.rawBody,
    this.envelope,
  });

  final int statusCode;
  final String? code;
  final String message;
  final String? traceId;
  final String? rawBody;
  final Map<String, dynamic>? envelope;

  String toDisplayMessage() {
    final headline = (code != null && code!.isNotEmpty)
        ? '$code: $message'
        : 'HTTP $statusCode: $message';
    if (traceId != null && traceId!.isNotEmpty) {
      return '$headline\ntrace_id: $traceId';
    }
    return headline;
  }

  @override
  String toString() => toDisplayMessage();
}

String formatApiError(Object error) {
  if (error is ApiException) {
    return error.toDisplayMessage();
  }
  final message = error.toString().trim();
  if (message.startsWith('Exception:')) {
    return message.substring('Exception:'.length).trim();
  }
  return message;
}
