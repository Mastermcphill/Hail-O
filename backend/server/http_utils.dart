import 'dart:convert';

import 'package:shelf/shelf.dart';

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
