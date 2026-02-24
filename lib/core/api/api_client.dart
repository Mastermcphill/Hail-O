import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;

import '../observability/app_observability.dart';
import '../storage/token_storage.dart';
import '../util/ids.dart';
import 'api_config.dart';
import 'api_error.dart';
import 'api_errors.dart';
import 'api_policy.dart';
import 'mock_backend_store.dart';

const String _mockNextOfKinKey = 'rider_next_of_kin_local';

class ApiClient {
  ApiClient({required TokenStorage tokenStorage, http.Client? httpClient})
    : _tokenStorage = tokenStorage,
      _httpClient = httpClient ?? http.Client();

  final TokenStorage _tokenStorage;
  final http.Client _httpClient;
  final _ApiCircuitBreaker _circuitBreaker = _ApiCircuitBreaker();

  Future<Map<String, dynamic>> get(String path) async {
    final normalizedPath = _normalizePath(path);
    if (_shouldUseMockByConfig(normalizedPath)) {
      return _mockResponse(method: 'GET', path: normalizedPath);
    }

    final policy = ApiPolicy.forRequest(method: 'GET');
    final requestId = newRequestId();
    _ensureCircuitClosed(requestId: requestId);
    final headers = await _buildHeaders(requestId: requestId);
    final uri = _buildUri(normalizedPath);
    for (var attempt = 0; ; attempt++) {
      _logRequest(
        requestId: requestId,
        method: 'GET',
        uri: uri,
        headers: headers,
        attempt: attempt,
      );
      try {
        final response = await _httpClient
            .get(uri, headers: headers)
            .timeout(policy.requestTimeout);
        final decoded = _decodeResponse(response);
        _recordRequestSuccess();
        return decoded;
      } on ApiException catch (error) {
        if (_shouldFallbackToMock(error, normalizedPath)) {
          final fallback = await _mockResponse(
            method: 'GET',
            path: normalizedPath,
          );
          _recordRequestSuccess();
          return fallback;
        }
        if (policy.shouldRetryApiException(error, attempt)) {
          await Future<void>.delayed(policy.retryDelay(attempt));
          continue;
        }
        _recordRequestFailure(error);
        rethrow;
      } on TimeoutException catch (error) {
        if (policy.shouldRetryTransportError(ApiErrorKind.timeout, attempt)) {
          await Future<void>.delayed(policy.retryDelay(attempt));
          continue;
        }
        final wrapped = ApiException(
          statusCode: 0,
          code: 'request_timeout',
          message: 'Request timed out.',
          rawBody: error.toString(),
        );
        _recordRequestFailure(wrapped);
        throw wrapped;
      } on SocketException catch (error) {
        if (policy.shouldRetryTransportError(ApiErrorKind.network, attempt)) {
          await Future<void>.delayed(policy.retryDelay(attempt));
          continue;
        }
        final wrapped = ApiException(
          statusCode: 0,
          code: 'network_error',
          message: 'Network request failed.',
          rawBody: error.toString(),
        );
        _recordRequestFailure(wrapped);
        throw wrapped;
      } on http.ClientException catch (error) {
        if (policy.shouldRetryTransportError(ApiErrorKind.network, attempt)) {
          await Future<void>.delayed(policy.retryDelay(attempt));
          continue;
        }
        final wrapped = ApiException(
          statusCode: 0,
          code: 'client_error',
          message: 'HTTP client request failed.',
          rawBody: error.toString(),
        );
        _recordRequestFailure(wrapped);
        throw wrapped;
      }
    }
  }

  Future<Map<String, dynamic>> post(
    String path, {
    Map<String, dynamic>? body,
    String? idempotencyKey,
  }) async {
    final normalizedPath = _normalizePath(path);
    final requestBody = body ?? <String, dynamic>{};
    if (_shouldUseMockByConfig(normalizedPath)) {
      return _mockResponse(
        method: 'POST',
        path: normalizedPath,
        body: requestBody,
      );
    }

    final callerProvidedIdempotencyKey =
        idempotencyKey != null && idempotencyKey.trim().isNotEmpty;
    final policy = ApiPolicy.forRequest(
      method: 'POST',
      hasIdempotencyKey: callerProvidedIdempotencyKey,
    );
    final requestId = newRequestId();
    _ensureCircuitClosed(requestId: requestId);
    final resolvedIdempotencyKey = callerProvidedIdempotencyKey
        ? idempotencyKey.trim()
        : newIdempotencyKey();
    final headers = await _buildHeaders(
      requestId: requestId,
      idempotencyKey: resolvedIdempotencyKey,
      includeJsonContentType: true,
    );
    final uri = _buildUri(normalizedPath);
    for (var attempt = 0; ; attempt++) {
      _logRequest(
        requestId: requestId,
        method: 'POST',
        uri: uri,
        headers: headers,
        attempt: attempt,
      );
      try {
        final response = await _httpClient
            .post(uri, headers: headers, body: jsonEncode(requestBody))
            .timeout(policy.requestTimeout);
        final decoded = _decodeResponse(response);
        _recordRequestSuccess();
        return decoded;
      } on ApiException catch (error) {
        if (_shouldFallbackToMock(error, normalizedPath)) {
          final fallback = await _mockResponse(
            method: 'POST',
            path: normalizedPath,
            body: requestBody,
          );
          _recordRequestSuccess();
          return fallback;
        }
        if (policy.shouldRetryApiException(error, attempt)) {
          await Future<void>.delayed(policy.retryDelay(attempt));
          continue;
        }
        _recordRequestFailure(error);
        rethrow;
      } on TimeoutException catch (error) {
        if (policy.shouldRetryTransportError(ApiErrorKind.timeout, attempt)) {
          await Future<void>.delayed(policy.retryDelay(attempt));
          continue;
        }
        final wrapped = ApiException(
          statusCode: 0,
          code: 'request_timeout',
          message: 'Request timed out.',
          rawBody: error.toString(),
        );
        _recordRequestFailure(wrapped);
        throw wrapped;
      } on SocketException catch (error) {
        if (policy.shouldRetryTransportError(ApiErrorKind.network, attempt)) {
          await Future<void>.delayed(policy.retryDelay(attempt));
          continue;
        }
        final wrapped = ApiException(
          statusCode: 0,
          code: 'network_error',
          message: 'Network request failed.',
          rawBody: error.toString(),
        );
        _recordRequestFailure(wrapped);
        throw wrapped;
      } on http.ClientException catch (error) {
        if (policy.shouldRetryTransportError(ApiErrorKind.network, attempt)) {
          await Future<void>.delayed(policy.retryDelay(attempt));
          continue;
        }
        final wrapped = ApiException(
          statusCode: 0,
          code: 'client_error',
          message: 'HTTP client request failed.',
          rawBody: error.toString(),
        );
        _recordRequestFailure(wrapped);
        throw wrapped;
      }
    }
  }

  Future<Map<String, dynamic>> patch(
    String path, {
    Map<String, dynamic>? body,
    String? idempotencyKey,
  }) async {
    final normalizedPath = _normalizePath(path);
    final requestBody = body ?? <String, dynamic>{};
    if (_shouldUseMockByConfig(normalizedPath)) {
      return _mockResponse(
        method: 'PATCH',
        path: normalizedPath,
        body: requestBody,
      );
    }

    final policy = ApiPolicy.forRequest(
      method: 'PATCH',
      hasIdempotencyKey:
          idempotencyKey != null && idempotencyKey.trim().isNotEmpty,
    );
    final requestId = newRequestId();
    _ensureCircuitClosed(requestId: requestId);
    final headers = await _buildHeaders(
      requestId: requestId,
      idempotencyKey: idempotencyKey,
      includeJsonContentType: true,
    );
    final uri = _buildUri(normalizedPath);
    for (var attempt = 0; ; attempt++) {
      _logRequest(
        requestId: requestId,
        method: 'PATCH',
        uri: uri,
        headers: headers,
        attempt: attempt,
      );
      try {
        final response = await _httpClient
            .patch(uri, headers: headers, body: jsonEncode(requestBody))
            .timeout(policy.requestTimeout);
        final decoded = _decodeResponse(response);
        _recordRequestSuccess();
        return decoded;
      } on ApiException catch (error) {
        if (_shouldFallbackToMock(error, normalizedPath)) {
          final fallback = await _mockResponse(
            method: 'PATCH',
            path: normalizedPath,
            body: requestBody,
          );
          _recordRequestSuccess();
          return fallback;
        }
        if (policy.shouldRetryApiException(error, attempt)) {
          await Future<void>.delayed(policy.retryDelay(attempt));
          continue;
        }
        _recordRequestFailure(error);
        rethrow;
      } on TimeoutException catch (error) {
        if (policy.shouldRetryTransportError(ApiErrorKind.timeout, attempt)) {
          await Future<void>.delayed(policy.retryDelay(attempt));
          continue;
        }
        final wrapped = ApiException(
          statusCode: 0,
          code: 'request_timeout',
          message: 'Request timed out.',
          rawBody: error.toString(),
        );
        _recordRequestFailure(wrapped);
        throw wrapped;
      } on SocketException catch (error) {
        if (policy.shouldRetryTransportError(ApiErrorKind.network, attempt)) {
          await Future<void>.delayed(policy.retryDelay(attempt));
          continue;
        }
        final wrapped = ApiException(
          statusCode: 0,
          code: 'network_error',
          message: 'Network request failed.',
          rawBody: error.toString(),
        );
        _recordRequestFailure(wrapped);
        throw wrapped;
      } on http.ClientException catch (error) {
        if (policy.shouldRetryTransportError(ApiErrorKind.network, attempt)) {
          await Future<void>.delayed(policy.retryDelay(attempt));
          continue;
        }
        final wrapped = ApiException(
          statusCode: 0,
          code: 'client_error',
          message: 'HTTP client request failed.',
          rawBody: error.toString(),
        );
        _recordRequestFailure(wrapped);
        throw wrapped;
      }
    }
  }

  Future<Map<String, dynamic>> delete(
    String path, {
    Map<String, dynamic>? body,
    String? idempotencyKey,
  }) async {
    final normalizedPath = _normalizePath(path);
    final requestBody = body ?? <String, dynamic>{};
    if (_shouldUseMockByConfig(normalizedPath)) {
      return _mockResponse(
        method: 'DELETE',
        path: normalizedPath,
        body: requestBody,
      );
    }

    final policy = ApiPolicy.forRequest(
      method: 'DELETE',
      hasIdempotencyKey:
          idempotencyKey != null && idempotencyKey.trim().isNotEmpty,
    );
    final requestId = newRequestId();
    _ensureCircuitClosed(requestId: requestId);
    final includeJsonContentType = requestBody.isNotEmpty;
    final headers = await _buildHeaders(
      requestId: requestId,
      idempotencyKey: idempotencyKey,
      includeJsonContentType: includeJsonContentType,
    );
    final uri = _buildUri(normalizedPath);
    for (var attempt = 0; ; attempt++) {
      _logRequest(
        requestId: requestId,
        method: 'DELETE',
        uri: uri,
        headers: headers,
        attempt: attempt,
      );
      try {
        http.Response response;
        if (requestBody.isEmpty) {
          response = await _httpClient
              .delete(uri, headers: headers)
              .timeout(policy.requestTimeout);
        } else {
          final request = http.Request('DELETE', uri);
          request.headers.addAll(headers);
          request.body = jsonEncode(requestBody);
          final streamed = await _httpClient
              .send(request)
              .timeout(policy.requestTimeout);
          response = await http.Response.fromStream(streamed);
        }
        final decoded = _decodeResponse(response);
        _recordRequestSuccess();
        return decoded;
      } on ApiException catch (error) {
        if (_shouldFallbackToMock(error, normalizedPath)) {
          final fallback = await _mockResponse(
            method: 'DELETE',
            path: normalizedPath,
            body: requestBody,
          );
          _recordRequestSuccess();
          return fallback;
        }
        if (policy.shouldRetryApiException(error, attempt)) {
          await Future<void>.delayed(policy.retryDelay(attempt));
          continue;
        }
        _recordRequestFailure(error);
        rethrow;
      } on TimeoutException catch (error) {
        if (policy.shouldRetryTransportError(ApiErrorKind.timeout, attempt)) {
          await Future<void>.delayed(policy.retryDelay(attempt));
          continue;
        }
        final wrapped = ApiException(
          statusCode: 0,
          code: 'request_timeout',
          message: 'Request timed out.',
          rawBody: error.toString(),
        );
        _recordRequestFailure(wrapped);
        throw wrapped;
      } on SocketException catch (error) {
        if (policy.shouldRetryTransportError(ApiErrorKind.network, attempt)) {
          await Future<void>.delayed(policy.retryDelay(attempt));
          continue;
        }
        final wrapped = ApiException(
          statusCode: 0,
          code: 'network_error',
          message: 'Network request failed.',
          rawBody: error.toString(),
        );
        _recordRequestFailure(wrapped);
        throw wrapped;
      } on http.ClientException catch (error) {
        if (policy.shouldRetryTransportError(ApiErrorKind.network, attempt)) {
          await Future<void>.delayed(policy.retryDelay(attempt));
          continue;
        }
        final wrapped = ApiException(
          statusCode: 0,
          code: 'client_error',
          message: 'HTTP client request failed.',
          rawBody: error.toString(),
        );
        _recordRequestFailure(wrapped);
        throw wrapped;
      }
    }
  }

  void close() {
    _httpClient.close();
  }

  Uri _buildUri(String normalizedPath) {
    return Uri.parse('${ApiConfig.baseUrl}$normalizedPath');
  }

  String _normalizePath(String path) {
    return path.startsWith('/') ? path : '/$path';
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

  void _logRequest({
    required String requestId,
    required String method,
    required Uri uri,
    required Map<String, String> headers,
    required int attempt,
  }) {
    unawaited(
      AppObservability.recordHttpRequest(
        requestId: requestId,
        method: method,
        uri: uri,
        attempt: attempt,
      ),
    );
    final redactedHeaders = _redactHeaders(headers);
    _debugLog(
      '[ApiClient][$requestId] ${method.toUpperCase()} $uri attempt=${attempt + 1} headers=$redactedHeaders',
    );
  }

  Map<String, String> _redactHeaders(Map<String, String> headers) {
    final redacted = <String, String>{...headers};
    const sensitiveKeys = <String>{
      'authorization',
      'idempotency-key',
      'x-idempotency-key',
      'x-api-key',
    };
    for (final entry in headers.entries) {
      if (sensitiveKeys.contains(entry.key.toLowerCase())) {
        redacted[entry.key] = '<redacted>';
      }
    }
    return redacted;
  }

  void _debugLog(String message) {
    assert(() {
      // ignore: avoid_print
      print(message);
      return true;
    }());
  }

  bool _shouldUseMockByConfig(String path) {
    return ApiConfig.mockMode && _isNewEndpointPath(path);
  }

  void _ensureCircuitClosed({required String requestId}) {
    if (_circuitBreaker.shouldAllowRequest()) {
      return;
    }
    throw ApiException(
      statusCode: 503,
      code: 'service_temporarily_unavailable',
      message: 'Service temporarily unavailable. Please try again shortly.',
      traceId: requestId,
    );
  }

  void _recordRequestSuccess() {
    _circuitBreaker.recordSuccess();
  }

  void _recordRequestFailure(ApiException error) {
    if (!_isFailureForCircuit(error)) {
      return;
    }
    _circuitBreaker.recordFailure();
  }

  bool _isFailureForCircuit(ApiException error) {
    final code = (error.code ?? '').trim().toLowerCase();
    if (code == 'request_timeout' ||
        code == 'network_error' ||
        code == 'client_error' ||
        code == 'service_temporarily_unavailable') {
      return true;
    }
    if (error.statusCode == 0) {
      return true;
    }
    if (error.statusCode == 502 ||
        error.statusCode == 503 ||
        error.statusCode == 504) {
      return true;
    }
    return error.statusCode >= 500;
  }

  bool _shouldFallbackToMock(ApiException error, String path) {
    if (!ApiConfig.mockMode) {
      return false;
    }
    return error.statusCode == 404 && _isNewEndpointPath(path);
  }

  bool _isNewEndpointPath(String path) {
    final uri = Uri.parse(path);
    final endpointPath = uri.path;
    if (endpointPath == '/me/next-of-kin') {
      return true;
    }
    if (endpointPath == '/routes' || endpointPath == '/routes/match') {
      return true;
    }
    final routePatterns = <RegExp>[
      RegExp(r'^/rides/[^/]+/offers$'),
      RegExp(r'^/rides/[^/]+/accept-offer$'),
      RegExp(r'^/rides/[^/]+/paywall/open$'),
      RegExp(r'^/rides/[^/]+/paywall/pay$'),
      RegExp(r'^/rides/[^/]+/seats$'),
      RegExp(r'^/rides/[^/]+/seats/select$'),
    ];
    return routePatterns.any((pattern) => pattern.hasMatch(endpointPath));
  }

  Future<Map<String, dynamic>> _mockResponse({
    required String method,
    required String path,
    Map<String, dynamic>? body,
  }) async {
    final uri = Uri.parse(path);
    final endpointPath = uri.path;

    if (endpointPath == '/me/next-of-kin') {
      if (method == 'GET') {
        final encoded = await _tokenStorage.readValue(_mockNextOfKinKey);
        if (encoded == null || encoded.trim().isEmpty) {
          throw ApiException(
            statusCode: 404,
            code: 'next_of_kin_not_found',
            message: 'Next-of-kin not set',
          );
        }
        final parsed = _tryParseJson(encoded);
        final map = _mapFromDynamic(parsed);
        return <String, dynamic>{'ok': true, 'next_of_kin': map};
      }
      final payload = body ?? <String, dynamic>{};
      await _tokenStorage.writeValue(_mockNextOfKinKey, jsonEncode(payload));
      return <String, dynamic>{'ok': true, 'next_of_kin': payload};
    }

    if (endpointPath == '/routes' && method == 'POST') {
      final payload = body ?? <String, dynamic>{};
      final route = <String, dynamic>{
        ...payload,
        'id': 'mock_route_${DateTime.now().millisecondsSinceEpoch}',
      };
      MockBackendStore.routeChains.add(route);
      return <String, dynamic>{'ok': true, 'route': route};
    }

    if (endpointPath == '/routes/match' && method == 'GET') {
      final from = uri.queryParameters['from'] ?? '';
      final to = uri.queryParameters['to'] ?? '';
      final matches = MockBackendStore.routeChains
          .where((route) {
            final nodes = route['nodes'];
            if (nodes is! List) {
              return true;
            }
            final lowered = nodes
                .whereType<Map>()
                .map((node) => (node['name'] ?? '').toString().toLowerCase())
                .toList();
            if (from.isEmpty || to.isEmpty) {
              return true;
            }
            return lowered.any((name) => name.contains(from.toLowerCase())) &&
                lowered.any((name) => name.contains(to.toLowerCase()));
          })
          .toList(growable: false);
      return <String, dynamic>{'ok': true, 'matches': matches};
    }

    final offersRideId = _rideIdFromPath(endpointPath, '/offers');
    if (offersRideId != null && method == 'GET') {
      final offers =
          MockBackendStore.offersByRideId[offersRideId] ?? _defaultMockOffers();
      MockBackendStore.offersByRideId.putIfAbsent(offersRideId, () => offers);
      return <String, dynamic>{'ok': true, 'offers': offers};
    }
    if (offersRideId != null && method == 'POST') {
      final payload = body ?? <String, dynamic>{};
      final offer = <String, dynamic>{
        ...payload,
        'offer_id': 'mock_offer_${DateTime.now().millisecondsSinceEpoch}',
        'price_minor': _readInt(payload['price_minor']),
        'vehicle_class': _readString(payload['vehicle_class']).isEmpty
            ? 'sedan'
            : _readString(payload['vehicle_class']),
        'luggage_supported': true,
      };
      MockBackendStore.offersByRideId.putIfAbsent(
        offersRideId,
        () => <Map<String, dynamic>>[],
      );
      MockBackendStore.offersByRideId[offersRideId]!.add(offer);
      return <String, dynamic>{'ok': true, 'offer': offer};
    }

    final acceptOfferRideId = _rideIdFromPath(endpointPath, '/accept-offer');
    if (acceptOfferRideId != null && method == 'POST') {
      final payload = body ?? <String, dynamic>{};
      final offerId = _readString(payload['offer_id']);
      final existingOffers =
          MockBackendStore.offersByRideId[acceptOfferRideId] ??
          _defaultMockOffers();
      final accepted = existingOffers.firstWhere(
        (offer) => _readString(offer['offer_id']) == offerId,
        orElse: () => existingOffers.first,
      );
      MockBackendStore.acceptedOfferByRideId[acceptOfferRideId] = accepted;
      return <String, dynamic>{
        'ok': true,
        'ride_id': acceptOfferRideId,
        'offer_id': _readString(accepted['offer_id']),
      };
    }

    final paywallOpenRideId = _rideIdFromPath(endpointPath, '/paywall/open');
    if (paywallOpenRideId != null && method == 'POST') {
      final paywall =
          MockBackendStore.paywallByRideId[paywallOpenRideId] ??
          <String, dynamic>{
            'connection_fee_minor': 1500,
            'deadline_at': DateTime.now()
                .toUtc()
                .add(const Duration(minutes: 10))
                .toIso8601String(),
          };
      MockBackendStore.paywallByRideId[paywallOpenRideId] = paywall;
      return <String, dynamic>{'ok': true, ...paywall};
    }

    final paywallPayRideId = _rideIdFromPath(endpointPath, '/paywall/pay');
    if (paywallPayRideId != null && method == 'POST') {
      return <String, dynamic>{
        'ok': true,
        'ride_id': paywallPayRideId,
        'paid': true,
      };
    }

    final seatsRideId = _rideIdFromPath(endpointPath, '/seats');
    if (seatsRideId != null && method == 'GET') {
      final seats =
          MockBackendStore.seatsByRideId[seatsRideId] ??
          <Map<String, dynamic>>[
            <String, dynamic>{'seat_id': 'FRONT_RIGHT', 'is_available': true},
            <String, dynamic>{'seat_id': 'BACK_LEFT', 'is_available': true},
            <String, dynamic>{'seat_id': 'BACK_MIDDLE', 'is_available': true},
            <String, dynamic>{'seat_id': 'BACK_RIGHT', 'is_available': true},
          ];
      MockBackendStore.seatsByRideId[seatsRideId] = seats;
      return <String, dynamic>{'ok': true, 'seats': seats};
    }

    final seatSelectRideId = _rideIdFromPath(endpointPath, '/seats/select');
    if (seatSelectRideId != null && method == 'POST') {
      final payload = body ?? <String, dynamic>{};
      final seatIds = (payload['seat_ids'] as List<dynamic>? ?? <dynamic>[])
          .map((value) => value.toString())
          .toList(growable: false);
      final purchaseId =
          'mock_purchase_${DateTime.now().millisecondsSinceEpoch}';
      MockBackendStore.selectedSeatIdsByRideId[seatSelectRideId] = seatIds;
      MockBackendStore.purchasesById[purchaseId] = <String, dynamic>{
        'purchase_id': purchaseId,
        'ride_id': seatSelectRideId,
        'seat_ids': seatIds,
        'pricing_minor': _readInt(payload['pricing_minor']),
        'status': 'CONFIRMED',
      };
      return <String, dynamic>{
        'ok': true,
        'purchase_id': purchaseId,
        'ride_id': seatSelectRideId,
        'seat_ids': seatIds,
        'pricing_minor': _readInt(payload['pricing_minor']),
      };
    }

    throw ApiException(
      statusCode: 404,
      message: 'No mock handler configured for $path',
      code: 'mock_not_found',
    );
  }

  String? _rideIdFromPath(String path, String suffix) {
    final pattern = RegExp('^/rides/([^/]+)${RegExp.escape(suffix)}\$');
    final match = pattern.firstMatch(path);
    return match?.group(1);
  }

  List<Map<String, dynamic>> _defaultMockOffers() {
    return <Map<String, dynamic>>[
      <String, dynamic>{
        'offer_id': 'mock_offer_1',
        'star_rating': 4.8,
        'gender': 'male',
        'tribe': 'yoruba',
        'vehicle_class': 'sedan',
        'luggage_supported': true,
        'price_minor': 4200,
      },
      <String, dynamic>{
        'offer_id': 'mock_offer_2',
        'star_rating': 4.5,
        'gender': 'female',
        'tribe': 'igbo',
        'vehicle_class': 'suv',
        'luggage_supported': true,
        'price_minor': 5600,
      },
      <String, dynamic>{
        'offer_id': 'mock_offer_3',
        'star_rating': 4.9,
        'gender': 'male',
        'tribe': 'hausa',
        'vehicle_class': 'hatchback',
        'luggage_supported': false,
        'price_minor': 3900,
      },
    ];
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
    final code =
        _stringOrNull(payload?['error_code']) ??
        _stringOrNull(payload?['code']);
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

  String _readString(Object? value) {
    if (value is String) {
      return value.trim();
    }
    return '';
  }

  int _readInt(Object? value) {
    if (value is int) {
      return value;
    }
    if (value is num) {
      return value.toInt();
    }
    if (value is String) {
      return int.tryParse(value.trim()) ?? 0;
    }
    return 0;
  }
}

class _ApiCircuitBreaker {
  static const int _failureThreshold = 4;
  static const Duration _window = Duration(seconds: 30);
  static const Duration _openDuration = Duration(seconds: 20);
  final List<DateTime> _failureTimestampsUtc = <DateTime>[];
  DateTime? _openUntilUtc;

  bool shouldAllowRequest() {
    final now = DateTime.now().toUtc();
    _pruneOldFailures(now);
    final openUntil = _openUntilUtc;
    if (openUntil == null) {
      return true;
    }
    if (openUntil.isAfter(now)) {
      return false;
    }
    _openUntilUtc = null;
    return true;
  }

  void recordSuccess() {
    _failureTimestampsUtc.clear();
    _openUntilUtc = null;
  }

  void recordFailure() {
    final now = DateTime.now().toUtc();
    _pruneOldFailures(now);
    _failureTimestampsUtc.add(now);
    if (_failureTimestampsUtc.length >= _failureThreshold) {
      _openUntilUtc = now.add(_openDuration);
      _failureTimestampsUtc.clear();
    }
  }

  void _pruneOldFailures(DateTime nowUtc) {
    _failureTimestampsUtc.removeWhere((timestamp) {
      return nowUtc.difference(timestamp) > _window;
    });
  }
}
