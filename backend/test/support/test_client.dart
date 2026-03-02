import 'dart:convert';

import 'package:shelf/shelf.dart';
import 'package:shelf/shelf.dart' as shelf;

import '../../infra/request_context.dart';

class BackendTestClient {
  const BackendTestClient({
    required Handler handler,
    required this.userId,
    required this.role,
    required this.traceId,
  }) : _handler = handler;

  final Handler _handler;
  final String userId;
  final String role;
  final String traceId;

  Future<BackendTestJsonResponse> get(
    String path, {
    Map<String, String> headers = const <String, String>{},
  }) {
    return _send('GET', path, headers: headers);
  }

  Future<BackendTestJsonResponse> post(
    String path, {
    Map<String, Object?> body = const <String, Object?>{},
    required String idempotencyKey,
    Map<String, String> headers = const <String, String>{},
  }) {
    return _send(
      'POST',
      path,
      headers: <String, String>{
        ...headers,
        'content-type': 'application/json',
        'idempotency-key': idempotencyKey,
      },
      body: jsonEncode(body),
    );
  }

  Future<BackendTestJsonResponse> _send(
    String method,
    String path, {
    Map<String, String> headers = const <String, String>{},
    String? body,
  }) async {
    final baseRequest = shelf.Request(
      method,
      Uri.parse('http://localhost$path'),
      headers: <String, String>{'x-trace-id': traceId, ...headers},
      body: body,
    );
    final request = RequestContext.withContext(
      baseRequest,
      RequestContext(traceId: traceId, userId: userId, role: role),
    );
    final response = await _handler(request);
    final rawBody = await response.readAsString();
    return BackendTestJsonResponse(
      statusCode: response.statusCode,
      headers: response.headers,
      body: rawBody,
    );
  }
}

class BackendTestJsonResponse {
  BackendTestJsonResponse({
    required this.statusCode,
    required this.headers,
    required this.body,
  }) : json = _decodeJsonObject(body);

  final int statusCode;
  final Map<String, String> headers;
  final String body;
  final Map<String, Object?> json;

  static Map<String, Object?> _decodeJsonObject(String rawBody) {
    if (rawBody.trim().isEmpty) {
      return const <String, Object?>{};
    }
    final decoded = jsonDecode(rawBody);
    if (decoded is Map<String, Object?>) {
      return decoded;
    }
    if (decoded is Map) {
      return decoded.map(
        (key, value) => MapEntry<String, Object?>(key.toString(), value),
      );
    }
    throw const FormatException('response_body_must_be_json_object');
  }
}
