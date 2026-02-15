import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:uuid/uuid.dart';

import 'api_config.dart';
import 'api_exception.dart';

class HailoBackendApiClient {
  HailoBackendApiClient({
    ApiConfig? config,
    http.Client? httpClient,
    Uuid? uuid,
  }) : _config = config ?? ApiConfig.fromEnvironment(),
       _httpClient = httpClient ?? http.Client(),
       _uuid = uuid ?? const Uuid();

  final ApiConfig _config;
  final http.Client _httpClient;
  final Uuid _uuid;

  String get baseUrl => _config.baseUrl;

  Future<Map<String, dynamic>> register({
    required String email,
    required String password,
    required String role,
    required String idempotencyKey,
    String? displayName,
  }) {
    return _postJson(
      path: '/auth/register',
      idempotencyKey: idempotencyKey,
      body: <String, Object?>{
        'email': email,
        'password': password,
        'role': role,
        if (displayName != null && displayName.trim().isNotEmpty)
          'display_name': displayName.trim(),
      },
    );
  }

  Future<Map<String, dynamic>> login({
    required String email,
    required String password,
  }) {
    return _postJson(
      path: '/auth/login',
      body: <String, Object?>{'email': email, 'password': password},
    );
  }

  Future<Map<String, dynamic>> requestRide({
    required String bearerToken,
    required String idempotencyKey,
    required DateTime scheduledDepartureAtUtc,
    required int distanceMeters,
    required int durationSeconds,
    required int luggageCount,
    required String vehicleClass,
    required int baseFareMinor,
    required int premiumMarkupMinor,
    required int connectionFeeMinor,
    String tripScope = 'intra_city',
    String? rideId,
    String? traceId,
  }) {
    return _postJson(
      path: '/rides/request',
      bearerToken: bearerToken,
      idempotencyKey: idempotencyKey,
      traceId: traceId,
      body: <String, Object?>{
        'scheduled_departure_at': scheduledDepartureAtUtc
            .toUtc()
            .toIso8601String(),
        'trip_scope': tripScope,
        'distance_meters': distanceMeters,
        'duration_seconds': durationSeconds,
        'luggage_count': luggageCount,
        'vehicle_class': vehicleClass,
        'base_fare_minor': baseFareMinor,
        'premium_markup_minor': premiumMarkupMinor,
        'connection_fee_minor': connectionFeeMinor,
        if (rideId != null && rideId.trim().isNotEmpty)
          'ride_id': rideId.trim(),
      },
    );
  }

  Future<Map<String, dynamic>> acceptRide({
    required String bearerToken,
    required String rideId,
    required String idempotencyKey,
    String? driverId,
    String? traceId,
  }) {
    return _postJson(
      path: '/rides/${Uri.encodeComponent(rideId)}/accept',
      bearerToken: bearerToken,
      idempotencyKey: idempotencyKey,
      traceId: traceId,
      body: <String, Object?>{
        if (driverId != null && driverId.trim().isNotEmpty)
          'driver_id': driverId.trim(),
      },
    );
  }

  Future<Map<String, dynamic>> cancelRide({
    required String bearerToken,
    required String rideId,
    required String idempotencyKey,
    String? traceId,
  }) {
    return _postJson(
      path: '/rides/${Uri.encodeComponent(rideId)}/cancel',
      bearerToken: bearerToken,
      idempotencyKey: idempotencyKey,
      traceId: traceId,
      body: const <String, Object?>{},
    );
  }

  Future<Map<String, dynamic>> completeRide({
    required String bearerToken,
    required String rideId,
    required String idempotencyKey,
    String settlementTrigger = 'manual_override',
    String? escrowId,
    String? traceId,
  }) {
    return _postJson(
      path: '/rides/${Uri.encodeComponent(rideId)}/complete',
      bearerToken: bearerToken,
      idempotencyKey: idempotencyKey,
      traceId: traceId,
      body: <String, Object?>{
        'settlement_trigger': settlementTrigger,
        if (escrowId != null && escrowId.trim().isNotEmpty)
          'escrow_id': escrowId.trim(),
      },
    );
  }

  Future<Map<String, dynamic>> getRideSnapshot({
    required String bearerToken,
    required String rideId,
    String? traceId,
  }) async {
    final headers = _buildHeaders(bearerToken: bearerToken, traceId: traceId);
    final uri = Uri.parse(
      '${_config.baseUrl}/rides/${Uri.encodeComponent(rideId)}',
    );
    final response = await _httpClient.get(uri, headers: headers);
    return _decodeResponse(response);
  }

  Future<Map<String, dynamic>> _postJson({
    required String path,
    required Map<String, Object?> body,
    String? bearerToken,
    String? idempotencyKey,
    String? traceId,
  }) async {
    final headers = _buildHeaders(
      bearerToken: bearerToken,
      idempotencyKey: idempotencyKey,
      traceId: traceId,
    );
    final uri = Uri.parse('${_config.baseUrl}$path');
    final response = await _httpClient.post(
      uri,
      headers: headers,
      body: jsonEncode(body),
    );
    return _decodeResponse(response);
  }

  Map<String, String> _buildHeaders({
    String? bearerToken,
    String? idempotencyKey,
    String? traceId,
  }) {
    final headers = <String, String>{
      'Content-Type': 'application/json',
      'Accept': 'application/json',
      'X-Trace-Id': (traceId == null || traceId.trim().isEmpty)
          ? _uuid.v4()
          : traceId.trim(),
    };
    if (bearerToken != null && bearerToken.trim().isNotEmpty) {
      headers['Authorization'] = 'Bearer ${bearerToken.trim()}';
    }
    if (idempotencyKey != null && idempotencyKey.trim().isNotEmpty) {
      headers['Idempotency-Key'] = idempotencyKey.trim();
    }
    return headers;
  }

  Map<String, dynamic> _decodeResponse(http.Response response) {
    final rawBody = response.body;
    final decoded = rawBody.isEmpty
        ? <String, dynamic>{}
        : jsonDecode(rawBody) as Map<String, dynamic>;
    if (response.statusCode >= 200 && response.statusCode < 300) {
      return decoded;
    }
    throw ApiException(
      statusCode: response.statusCode,
      code: (decoded['code'] as String?) ?? 'http_${response.statusCode}',
      message:
          (decoded['message'] as String?) ??
          (decoded['error'] as String?) ??
          'Request failed',
      traceId: decoded['trace_id'] as String?,
      rawBody: rawBody,
    );
  }
}
