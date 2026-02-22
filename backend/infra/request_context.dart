import 'package:shelf/shelf.dart';

class RequestContext {
  const RequestContext({
    required this.traceId,
    this.userId,
    this.role,
    this.idempotencyKey,
  });

  static const String contextKey = 'hailo.request_context';

  final String traceId;
  final String? userId;
  final String? role;
  final String? idempotencyKey;

  RequestContext copyWith({
    String? traceId,
    String? userId,
    String? role,
    String? idempotencyKey,
  }) {
    return RequestContext(
      traceId: traceId ?? this.traceId,
      userId: userId ?? this.userId,
      role: role ?? this.role,
      idempotencyKey: idempotencyKey ?? this.idempotencyKey,
    );
  }

  Map<String, Object?> toMap() {
    return <String, Object?>{
      'trace_id': traceId,
      'user_id': userId,
      'role': role,
      'idempotency_key': idempotencyKey,
    };
  }

  static RequestContext fromRequest(Request request) {
    final existing = request.context[contextKey];
    if (existing is RequestContext) {
      return existing;
    }
    return const RequestContext(traceId: 'trace-unset');
  }

  static Request withContext(Request request, RequestContext context) {
    return request.change(
      context: <String, Object?>{...request.context, contextKey: context},
    );
  }
}

extension RequestContextExtension on Request {
  RequestContext get requestContext => RequestContext.fromRequest(this);
}
