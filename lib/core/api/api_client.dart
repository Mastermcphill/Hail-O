import 'dart:convert';

import 'package:http/http.dart' as http;

import '../storage/token_storage.dart';
import '../util/ids.dart';
import 'api_config.dart';
import 'api_errors.dart';

class ApiClient {
  ApiClient({
    required TokenStorage tokenStorage,
    http.Client? httpClient,
  }) : _tokenStorage = tokenStorage,
       _httpClient = httpClient ?? http.Client();

  final TokenStorage _tokenStorage;
  final http.Client _httpClient;

  Future<Map<String, dynamic>> get(String path) async {
    final requestId = newRequestId();
    final headers = await _buildHeaders(requestId: requestId);
    final response = await _httpClient.get(
      _buildUri(path),
      headers: headers,
    );
    return _decodeResponse(response);
  }

  Future<Map<String, dynamic>> post(
    String path, {
    Map<String, dynamic>? body,
  }) async {
    final requestId = newRequestId();
    final idempotencyKey = newIdempotencyKey();
    final headers = await _buildHeaders(
      requestId: requestId,
      idempotencyKey: idempotencyKey,
      includeJsonContentType: true,
    );
    final response = await _httpClient.post(
      _buildUri(path),
      headers: headers,
      body: jsonEncode(body ?? <String, dynamic>{}),
    );
    return _decodeResponse(response);
  }

  void close() {
    _httpClient.close();
  }

  Uri _buildUri(String path) {
    final normalizedPath = path.startsWith('/') ? path : '/$path';
    return Uri.parse('${ApiConfig.baseUrl}$normalizedPath');
  }

  Future<Map<String, String>> _buildHeaders({
    required String requestId,
    String? idempotencyKey,
    bool includeJsonContentType = false,
  }) async {
    final headers = <String, String>{
      'Accept': 'application/json',
      'X-Request-ID': requestId,
      'X-Trace-ID': requestId,
    };
    if (includeJsonContentType) {
      headers['Content-Type'] = 'application/json';
    }
    if (idempotencyKey != null && idempotencyKey.isNotEmpty) {
      headers['X-Idempotency-Key'] = idempotencyKey;
      // Backend currently enforces this header value on all write routes.
      headers['Idempotency-Key'] = idempotencyKey;
    }
    final token = await _tokenStorage.readToken();
    if (token != null && token.isNotEmpty) {
      headers['Authorization'] = 'Bearer $token';
    }
    return headers;
  }

  Map<String, dynamic> _decodeResponse(http.Response response) {
    final rawBody = response.body;
    final decodedBody = _tryParseJson(rawBody);
    final payload = decodedBody != null ? _mapFromDynamic(decodedBody) : null;

    if (response.statusCode >= 400) {
      throw _buildException(
        statusCode: response.statusCode,
        payload: payload,
        rawBody: rawBody,
      );
    }

    if (payload != null && payload.containsKey('ok') && payload['ok'] != true) {
      throw _buildException(
        statusCode: response.statusCode,
        payload: payload,
        rawBody: rawBody,
      );
    }

    if (payload != null) {
      return payload;
    }

    if (rawBody.trim().isEmpty) {
      return <String, dynamic>{};
    }
    return <String, dynamic>{'raw_body': rawBody};
  }

  ApiException _buildException({
    required int statusCode,
    required Map<String, dynamic>? payload,
    required String rawBody,
  }) {
    final code = _stringOrNull(payload?['code']);
    final traceId = _stringOrNull(payload?['trace_id']);
    final rawMessage = rawBody.trim();
    final message =
        _stringOrNull(payload?['message']) ??
        (rawMessage.isNotEmpty
            ? rawMessage
            : (statusCode >= 400
                  ? 'Request failed with status $statusCode'
                  : 'Response contained ok=false'));

    return ApiException(
      statusCode: statusCode,
      code: code,
      message: message,
      traceId: traceId,
      rawBody: rawBody,
      envelope: payload,
    );
  }

  dynamic _tryParseJson(String rawBody) {
    if (rawBody.trim().isEmpty) {
      return <String, dynamic>{};
    }
    try {
      return jsonDecode(rawBody);
    } catch (_) {
      return null;
    }
  }

  Map<String, dynamic> _mapFromDynamic(dynamic value) {
    if (value is Map<String, dynamic>) {
      return value;
    }
    if (value is Map) {
      return value.map(
        (key, item) => MapEntry<String, dynamic>(key.toString(), item),
      );
    }
    return <String, dynamic>{'data': value};
  }

  String? _stringOrNull(Object? value) {
    if (value is String && value.trim().isNotEmpty) {
      return value.trim();
    }
    return null;
  }
}
