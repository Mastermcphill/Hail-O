import 'package:shelf/shelf.dart';
import 'package:uuid/uuid.dart';

import '../../infra/request_context.dart';
import '../../server/http_utils.dart';

Response marketplaceOk(
  Request request, {
  required Object? data,
  int statusCode = 200,
  Map<String, String>? headers,
}) {
  return jsonResponse(statusCode, <String, Object?>{
    'ok': true,
    'trace_id': _resolveTraceId(request),
    'data': data,
  }, headers: headers);
}

Response marketplaceError(
  Request request, {
  required int statusCode,
  required String errorCode,
  required String message,
  Object? data,
  Map<String, String>? headers,
}) {
  final payload = <String, Object?>{
    'ok': false,
    'trace_id': _resolveTraceId(request),
    'error_code': errorCode,
    'message': message,
  };
  if (data != null) {
    payload['data'] = data;
  }
  return jsonResponse(
    statusCode,
    payload,
    headers: <String, String>{'x-error-code': errorCode, ...?headers},
  );
}

String _resolveTraceId(Request request) {
  final contextTraceId = request.requestContext.traceId.trim();
  if (contextTraceId.isNotEmpty && contextTraceId != 'trace-unset') {
    return contextTraceId;
  }
  final headerTraceId = (request.headers['x-trace-id'] ?? '').trim();
  if (headerTraceId.isNotEmpty) {
    return headerTraceId;
  }
  return const Uuid().v4();
}
