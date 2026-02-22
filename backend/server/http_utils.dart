import 'dart:convert';

import 'package:shelf/shelf.dart';
import 'package:uuid/uuid.dart';

import '../infra/request_context.dart';

Response jsonResponse(
  int statusCode,
  Object? body, {
  Map<String, String>? headers,
}) {
  return Response(
    statusCode,
    body: jsonEncode(body),
    headers: <String, String>{'content-type': 'application/json', ...?headers},
  );
}

Map<String, Object?> errorEnvelope(
  Request request, {
  required String code,
  required String message,
}) {
  final contextTraceId = request.requestContext.traceId.trim();
  final headerTraceId = (request.headers['x-trace-id'] ?? '').trim();
  final traceId = (contextTraceId.isNotEmpty && contextTraceId != 'trace-unset')
      ? contextTraceId
      : (headerTraceId.isNotEmpty ? headerTraceId : const Uuid().v4());
  return <String, Object?>{
    'ok': false,
    'code': code,
    'message': message,
    'trace_id': traceId,
  };
}

Response jsonErrorResponse(
  Request request,
  int statusCode, {
  required String code,
  required String message,
  Map<String, String>? headers,
}) {
  return jsonResponse(
    statusCode,
    errorEnvelope(request, code: code, message: message),
    headers: <String, String>{'x-error-code': code, ...?headers},
  );
}

Future<Map<String, Object?>> readJsonBody(Request request) async {
  final raw = await request.readAsString();
  if (raw.trim().isEmpty) {
    return <String, Object?>{};
  }
  final decoded = jsonDecode(raw);
  if (decoded is! Map<String, dynamic>) {
    throw const FormatException('request_body_must_be_json_object');
  }
  return Map<String, Object?>.from(decoded);
}
