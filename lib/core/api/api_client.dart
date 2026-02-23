import 'dart:convert';

import 'package:http/http.dart' as http;

import '../storage/token_storage.dart';
import '../util/ids.dart';
import 'api_config.dart';
import 'api_errors.dart';
import 'api_paths.dart';

class ApiResult {
  const ApiResult({
    required this.statusCode,
    required this.headers,
    required this.data,
  });

  final int statusCode;
  final Map<String, String> headers;
  final Map<String, dynamic> data;

  bool get notModified => statusCode == 304;
}

class ApiClient {
  ApiClient({required TokenStorage tokenStorage, http.Client? httpClient})
    : _tokenStorage = tokenStorage,
      _httpClient = httpClient ?? http.Client();

  static const _mockNextOfKinKey = 'mock_next_of_kin';

  final TokenStorage _tokenStorage;
  final http.Client _httpClient;

  Future<Map<String, dynamic>> get(String path) async {
    final result = await getDetailed(path);
    return result.data;
  }

  Future<ApiResult> getDetailed(
    String path, {
    Map<String, String>? extraHeaders,
  }) async {
    final normalizedPath = _normalizePath(path);
    if (ApiConfig.mockMode && _supportsMock('GET', normalizedPath)) {
      return ApiResult(
        statusCode: 200,
        headers: const <String, String>{},
        data: await _mockGet(normalizedPath),
      );
    }

    try {
      return _send(
        method: 'GET',
        path: normalizedPath,
        extraHeaders: extraHeaders,
      );
    } on ApiException catch (error) {
      if (error.statusCode == 404 && _supportsMock('GET', normalizedPath)) {
        return ApiResult(
          statusCode: 200,
          headers: const <String, String>{},
          data: await _mockGet(normalizedPath),
        );
      }
      rethrow;
    } catch (_) {
      if (ApiConfig.mockMode && _supportsMock('GET', normalizedPath)) {
        return ApiResult(
          statusCode: 200,
          headers: const <String, String>{},
          data: await _mockGet(normalizedPath),
        );
      }
      rethrow;
    }
  }

  Future<Map<String, dynamic>> post(
    String path, {
    Map<String, dynamic>? body,
  }) async {
    final result = await postDetailed(path, body: body);
    return result.data;
  }

  Future<ApiResult> postDetailed(
    String path, {
    Map<String, dynamic>? body,
    Map<String, String>? extraHeaders,
    String? idempotencyKey,
  }) async {
    final normalizedPath = _normalizePath(path);
    final payload = body ?? <String, dynamic>{};
    if (ApiConfig.mockMode && _supportsMock('POST', normalizedPath)) {
      return ApiResult(
        statusCode: 200,
        headers: const <String, String>{},
        data: await _mockPost(normalizedPath, payload),
      );
    }

    try {
      final result = await _send(
        method: 'POST',
        path: normalizedPath,
        body: payload,
        extraHeaders: extraHeaders,
        idempotencyKey: idempotencyKey ?? newIdempotencyKey(),
      );
      if (normalizedPath == ApiPaths.ridesRequest) {
        _rememberRideContext(requestBody: payload, responseBody: result.data);
      }
      return result;
    } on ApiException catch (error) {
      if (error.statusCode == 404 && _supportsMock('POST', normalizedPath)) {
        return ApiResult(
          statusCode: 200,
          headers: const <String, String>{},
          data: await _mockPost(normalizedPath, payload),
        );
      }
      rethrow;
    } catch (_) {
      if (ApiConfig.mockMode && _supportsMock('POST', normalizedPath)) {
        return ApiResult(
          statusCode: 200,
          headers: const <String, String>{},
          data: await _mockPost(normalizedPath, payload),
        );
      }
      rethrow;
    }
  }

  Future<ApiResult> patchDetailed(
    String path, {
    Map<String, dynamic>? body,
    Map<String, String>? extraHeaders,
  }) {
    final normalizedPath = _normalizePath(path);
    return _send(
      method: 'PATCH',
      path: normalizedPath,
      body: body ?? const <String, dynamic>{},
      extraHeaders: extraHeaders,
    );
  }

  void close() {
    _httpClient.close();
  }

  Uri _buildUri(String normalizedPath) {
    return Uri.parse('${ApiConfig.baseUrl}$normalizedPath');
  }

  String _normalizePath(String path) {
    final trimmed = path.trim();
    if (trimmed.startsWith('/')) {
      return trimmed;
    }
    return '/$trimmed';
  }

  Future<Map<String, String>> _buildHeaders({
    required String requestId,
    String? idempotencyKey,
    bool includeJsonContentType = false,
    Map<String, String>? extraHeaders,
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
      headers['Idempotency-Key'] = idempotencyKey;
    }
    final token = await _tokenStorage.readToken();
    if (token != null && token.isNotEmpty) {
      headers['Authorization'] = 'Bearer $token';
    }
    if (extraHeaders != null && extraHeaders.isNotEmpty) {
      headers.addAll(extraHeaders);
    }
    return headers;
  }

  Future<ApiResult> _send({
    required String method,
    required String path,
    Map<String, dynamic>? body,
    Map<String, String>? extraHeaders,
    String? idempotencyKey,
  }) async {
    final requestId = newRequestId();
    final includeBody =
        method == 'POST' || method == 'PATCH' || method == 'PUT';
    final headers = await _buildHeaders(
      requestId: requestId,
      idempotencyKey: idempotencyKey,
      includeJsonContentType: includeBody,
      extraHeaders: extraHeaders,
    );

    late final http.Response response;
    final uri = _buildUri(path);
    switch (method.toUpperCase()) {
      case 'GET':
        response = await _httpClient.get(uri, headers: headers);
        break;
      case 'POST':
        response = await _httpClient.post(
          uri,
          headers: headers,
          body: jsonEncode(body ?? const <String, dynamic>{}),
        );
        break;
      case 'PATCH':
        response = await _httpClient.patch(
          uri,
          headers: headers,
          body: jsonEncode(body ?? const <String, dynamic>{}),
        );
        break;
      case 'PUT':
        response = await _httpClient.put(
          uri,
          headers: headers,
          body: jsonEncode(body ?? const <String, dynamic>{}),
        );
        break;
      default:
        throw UnsupportedError('Unsupported HTTP method: $method');
    }

    return _decodeResponse(response);
  }

  ApiResult _decodeResponse(http.Response response) {
    if (response.statusCode == 304) {
      return ApiResult(
        statusCode: response.statusCode,
        headers: response.headers,
        data: const <String, dynamic>{},
      );
    }

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
      return ApiResult(
        statusCode: response.statusCode,
        headers: response.headers,
        data: payload,
      );
    }

    if (rawBody.trim().isEmpty) {
      return ApiResult(
        statusCode: response.statusCode,
        headers: response.headers,
        data: const <String, dynamic>{},
      );
    }
    return ApiResult(
      statusCode: response.statusCode,
      headers: response.headers,
      data: <String, dynamic>{'raw_body': rawBody},
    );
  }

  ApiException _buildException({
    required int statusCode,
    required Map<String, dynamic>? payload,
    required String rawBody,
  }) {
    final code =
        _stringOrNull(payload?['code']) ??
        _stringOrNull(payload?['error_code']);
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

  bool _supportsMock(String method, String path) {
    final uri = Uri.parse('https://mock.local$path');
    final segments = uri.pathSegments;
    if (segments.isEmpty) {
      return false;
    }

    if (uri.path == ApiPaths.meNextOfKin) {
      return method == 'GET' || method == 'POST';
    }

    if (uri.path == ApiPaths.routesCreate && method == 'POST') {
      return true;
    }
    if (uri.path == '/routes/match' && method == 'GET') {
      return true;
    }

    if (uri.path == ApiPaths.ridesRequest && method == 'POST') {
      return true;
    }

    if (segments.length == 2 && segments[0] == 'rides' && method == 'GET') {
      return true;
    }

    if (segments.length == 3 && segments[0] == 'rides') {
      final action = segments[2];
      if (action == 'offers' && (method == 'GET' || method == 'POST')) {
        return true;
      }
      if (action == 'accept-offer' && method == 'POST') {
        return true;
      }
      if (action == 'seats' && method == 'GET') {
        return true;
      }
      if (action == 'cancel' && method == 'POST') {
        return true;
      }
    }

    if (segments.length == 4 &&
        segments[0] == 'rides' &&
        segments[2] == 'paywall' &&
        (segments[3] == 'open' || segments[3] == 'pay') &&
        method == 'POST') {
      return true;
    }

    if (segments.length == 4 &&
        segments[0] == 'rides' &&
        segments[2] == 'seats' &&
        segments[3] == 'select' &&
        method == 'POST') {
      return true;
    }

    return false;
  }

  Future<Map<String, dynamic>> _mockGet(String path) async {
    final uri = Uri.parse('https://mock.local$path');
    final segments = uri.pathSegments;

    if (uri.path == ApiPaths.meNextOfKin) {
      final raw = await _tokenStorage.readValue(_mockNextOfKinKey);
      if (raw == null || raw.trim().isEmpty) {
        throw ApiException(
          statusCode: 404,
          code: 'next_of_kin_not_set',
          message: 'Next of kin has not been configured',
          traceId: newRequestId(),
          rawBody: raw ?? '',
        );
      }
      return _withMock(<String, dynamic>{
        'ok': true,
        'next_of_kin': _mapFromDynamic(jsonDecode(raw)),
      });
    }

    if (uri.path == '/routes/match') {
      final from = uri.queryParameters['from'] ?? '';
      final to = uri.queryParameters['to'] ?? '';
      return _withMock(<String, dynamic>{
        'ok': true,
        'routes': _MockRideStore.matchRoutes(from: from, to: to),
      });
    }

    final rideId = _rideIdFromSegments(segments);
    if (rideId != null && segments.length == 2) {
      return _withMock(_MockRideStore.snapshot(rideId));
    }
    if (rideId != null && segments.length == 3 && segments[2] == 'offers') {
      return _withMock(<String, dynamic>{
        'ok': true,
        'offers': _MockRideStore.getOffers(rideId),
      });
    }
    if (rideId != null && segments.length == 3 && segments[2] == 'seats') {
      return _withMock(<String, dynamic>{
        'ok': true,
        ..._MockRideStore.getSeats(rideId),
      });
    }

    throw ApiException(
      statusCode: 404,
      code: 'mock_route_not_found',
      message: 'Mock handler not found for GET $path',
      traceId: newRequestId(),
      rawBody: path,
    );
  }

  Future<Map<String, dynamic>> _mockPost(
    String path,
    Map<String, dynamic> body,
  ) async {
    final uri = Uri.parse('https://mock.local$path');
    final segments = uri.pathSegments;

    if (uri.path == ApiPaths.meNextOfKin) {
      await _tokenStorage.writeValue(_mockNextOfKinKey, jsonEncode(body));
      return _withMock(<String, dynamic>{'ok': true, 'next_of_kin': body});
    }

    if (uri.path == ApiPaths.routesCreate) {
      return _withMock(<String, dynamic>{
        'ok': true,
        'route': _MockRideStore.saveRouteChain(body),
      });
    }

    if (uri.path == ApiPaths.ridesRequest) {
      final created = _MockRideStore.createRide(body);
      return _withMock(<String, dynamic>{'ok': true, ...created});
    }

    final rideId = _rideIdFromSegments(segments);
    if (rideId != null && segments.length == 3 && segments[2] == 'offers') {
      return _withMock(<String, dynamic>{
        'ok': true,
        'offer': _MockRideStore.submitDriverOffer(rideId, body),
      });
    }
    if (rideId != null &&
        segments.length == 3 &&
        segments[2] == 'accept-offer') {
      return _withMock(
        _MockRideStore.acceptOffer(rideId, body['offer_id']?.toString()),
      );
    }
    if (rideId != null &&
        segments.length == 4 &&
        segments[2] == 'paywall' &&
        segments[3] == 'open') {
      return _withMock(_MockRideStore.openPaywall(rideId));
    }
    if (rideId != null &&
        segments.length == 4 &&
        segments[2] == 'paywall' &&
        segments[3] == 'pay') {
      return _withMock(_MockRideStore.payPaywall(rideId));
    }
    if (rideId != null &&
        segments.length == 4 &&
        segments[2] == 'seats' &&
        segments[3] == 'select') {
      final seatIds = (body['seat_ids'] as List<dynamic>? ?? const <dynamic>[])
          .map((item) => item.toString())
          .toList(growable: false);
      return _withMock(
        _MockRideStore.selectSeats(
          rideId,
          seatIds: seatIds,
          pricingMinor: (body['pricing_minor'] as num?)?.toInt() ?? 0,
        ),
      );
    }
    if (rideId != null && segments.length == 3 && segments[2] == 'cancel') {
      return _withMock(_MockRideStore.cancelRide(rideId));
    }

    throw ApiException(
      statusCode: 404,
      code: 'mock_route_not_found',
      message: 'Mock handler not found for POST $path',
      traceId: newRequestId(),
      rawBody: path,
    );
  }

  String? _rideIdFromSegments(List<String> segments) {
    if (segments.length < 2 || segments[0] != 'rides') {
      return null;
    }
    return segments[1];
  }

  void _rememberRideContext({
    required Map<String, dynamic> requestBody,
    required Map<String, dynamic> responseBody,
  }) {
    final rideId =
        _stringOrNull(responseBody['ride_id']) ??
        _stringOrNull(responseBody['id']) ??
        _stringOrNull(_mapFromDynamic(responseBody['ride'])['id']);
    if (rideId == null) {
      return;
    }
    _MockRideStore.ensureRide(
      rideId: rideId,
      luggageCount: (requestBody['luggage_count'] as num?)?.toInt() ?? 0,
      charterMode: requestBody['charter_mode'] == true,
      basePriceMinor: (requestBody['base_fare_minor'] as num?)?.toInt() ?? 0,
      pickup: requestBody['pickup']?.toString(),
      dropoff: requestBody['dropoff']?.toString(),
    );
  }

  Map<String, dynamic> _withMock(Map<String, dynamic> payload) {
    return <String, dynamic>{'mock_mode': true, ...payload};
  }
}

class _MockRideStore {
  static final Map<String, Map<String, dynamic>> _rides =
      <String, Map<String, dynamic>>{};
  static final Map<String, List<Map<String, dynamic>>> _offersByRide =
      <String, List<Map<String, dynamic>>>{};
  static final Map<String, Map<String, dynamic>> _paywallByRide =
      <String, Map<String, dynamic>>{};
  static final Map<String, List<String>> _selectedSeatsByRide =
      <String, List<String>>{};
  static final List<Map<String, dynamic>> _routeChains =
      <Map<String, dynamic>>[];

  static int _seq = 0;

  static Map<String, dynamic> createRide(Map<String, dynamic> payload) {
    final rideId =
        'mock-ride-${DateTime.now().millisecondsSinceEpoch}-${_seq++}';
    ensureRide(
      rideId: rideId,
      luggageCount: (payload['luggage_count'] as num?)?.toInt() ?? 0,
      charterMode: payload['charter_mode'] == true,
      basePriceMinor: (payload['base_fare_minor'] as num?)?.toInt() ?? 7000,
      pickup: payload['pickup']?.toString(),
      dropoff: payload['dropoff']?.toString(),
    );
    return <String, dynamic>{'ride_id': rideId};
  }

  static void ensureRide({
    required String rideId,
    required int luggageCount,
    required bool charterMode,
    required int basePriceMinor,
    String? pickup,
    String? dropoff,
  }) {
    _rides.putIfAbsent(rideId, () {
      return <String, dynamic>{
        'id': rideId,
        'status': 'REQUESTED',
        'state': 'REQUESTED',
        'rider_id': 'mock-rider',
        'driver_id': null,
        'luggage_count': luggageCount,
        'charter_mode': charterMode,
        'base_price_minor': basePriceMinor > 0 ? basePriceMinor : 7000,
        'pickup': pickup,
        'dropoff': dropoff,
      };
    });
  }

  static Map<String, dynamic> snapshot(String rideId) {
    final ride = _rides[rideId];
    if (ride == null) {
      throw ApiException(
        statusCode: 404,
        code: 'ride_not_found',
        message: 'Ride not found in mock store',
        traceId: newRequestId(),
        rawBody: rideId,
      );
    }
    return <String, dynamic>{
      'ok': true,
      'ride_id': rideId,
      'status': ride['status'],
      'state': ride['state'],
      'ride': ride,
      'accepted_offer_id': ride['accepted_offer_id'],
      'selected_seats': _selectedSeatsByRide[rideId] ?? <String>[],
      'paywall': _paywallByRide[rideId],
    };
  }

  static List<Map<String, dynamic>> getOffers(String rideId) {
    _rides.putIfAbsent(rideId, () {
      return <String, dynamic>{
        'id': rideId,
        'status': 'OFFERED',
        'state': 'OFFERED',
        'rider_id': 'mock-rider',
        'base_price_minor': 7000,
        'luggage_count': 0,
        'charter_mode': false,
      };
    });
    final offers = _offersByRide.putIfAbsent(rideId, () {
      return <Map<String, dynamic>>[
        <String, dynamic>{
          'offer_id': 'offer-$rideId-1',
          'star_rating': 4.8,
          'gender': 'male',
          'tribe': 'Yoruba',
          'vehicle_class': 'suv',
          'luggage_supported': true,
          'price_minor': 9000,
        },
        <String, dynamic>{
          'offer_id': 'offer-$rideId-2',
          'star_rating': 4.5,
          'gender': 'female',
          'tribe': 'Igbo',
          'vehicle_class': 'sedan',
          'luggage_supported': true,
          'price_minor': 7800,
        },
        <String, dynamic>{
          'offer_id': 'offer-$rideId-3',
          'star_rating': 4.2,
          'gender': 'male',
          'vehicle_class': 'hatchback',
          'luggage_supported': false,
          'price_minor': 6900,
        },
      ];
    });
    final ride = _rides[rideId];
    if (ride != null) {
      ride['status'] = 'OFFERED';
      ride['state'] = 'OFFERED';
    }
    return offers;
  }

  static Map<String, dynamic> submitDriverOffer(
    String rideId,
    Map<String, dynamic> body,
  ) {
    final offer = <String, dynamic>{
      'offer_id': 'driver-offer-$rideId-${_seq++}',
      'star_rating': (body['star_rating'] as num?)?.toDouble() ?? 4.7,
      'gender': body['gender']?.toString(),
      'tribe': body['tribe']?.toString(),
      'vehicle_class': body['vehicle_class']?.toString() ?? 'sedan',
      'luggage_supported': body['luggage_supported'] ?? true,
      'price_minor': (body['price_minor'] as num?)?.toInt() ?? 7500,
    };
    final offers = _offersByRide.putIfAbsent(
      rideId,
      () => <Map<String, dynamic>>[],
    );
    offers.add(offer);
    final ride = _rides[rideId];
    if (ride != null) {
      ride['status'] = 'OFFERED';
      ride['state'] = 'OFFERED';
    }
    return offer;
  }

  static Map<String, dynamic> acceptOffer(String rideId, String? offerId) {
    final offers = getOffers(rideId);
    final selected = offers.firstWhere(
      (item) => item['offer_id'] == offerId,
      orElse: () => offers.first,
    );
    final ride = _rides[rideId];
    if (ride == null) {
      throw ApiException(
        statusCode: 404,
        code: 'ride_not_found',
        message: 'Ride not found in mock store',
        traceId: newRequestId(),
        rawBody: rideId,
      );
    }
    ride['accepted_offer_id'] = selected['offer_id'];
    ride['driver_id'] = 'mock-driver';
    ride['base_price_minor'] = selected['price_minor'];
    ride['status'] = 'ACCEPTED';
    ride['state'] = 'ACCEPTED';
    return <String, dynamic>{
      'ok': true,
      'ride_id': rideId,
      'offer_id': selected['offer_id'],
      'price_minor': selected['price_minor'],
    };
  }

  static Map<String, dynamic> openPaywall(String rideId) {
    final ride = _rides[rideId];
    if (ride == null) {
      throw ApiException(
        statusCode: 404,
        code: 'ride_not_found',
        message: 'Ride not found in mock store',
        traceId: newRequestId(),
        rawBody: rideId,
      );
    }
    final connectionFeeMinor =
        ((ride['base_price_minor'] as int? ?? 7000) * 0.1).round().clamp(
          500,
          5000,
        );
    final deadlineAt = DateTime.now().toUtc().add(const Duration(minutes: 10));
    final payload = <String, dynamic>{
      'connection_fee_minor': connectionFeeMinor,
      'deadline_at': deadlineAt.toIso8601String(),
      'paid': false,
    };
    _paywallByRide[rideId] = payload;
    ride['status'] = 'PAYWALL_PENDING';
    ride['state'] = 'PAYWALL_PENDING';
    return <String, dynamic>{'ok': true, ...payload};
  }

  static Map<String, dynamic> payPaywall(String rideId) {
    final ride = _rides[rideId];
    final paywall = _paywallByRide[rideId];
    if (ride == null || paywall == null) {
      throw ApiException(
        statusCode: 409,
        code: 'paywall_not_open',
        message: 'Open paywall before payment',
        traceId: newRequestId(),
        rawBody: rideId,
      );
    }
    final deadline = DateTime.tryParse(
      paywall['deadline_at']?.toString() ?? '',
    )?.toUtc();
    if (deadline != null && DateTime.now().toUtc().isAfter(deadline)) {
      throw ApiException(
        statusCode: 409,
        code: 'paywall_expired',
        message: 'Connection fee window expired',
        traceId: newRequestId(),
        rawBody: rideId,
      );
    }
    paywall['paid'] = true;
    ride['status'] = 'CONFIRMED';
    ride['state'] = 'CONFIRMED';
    return <String, dynamic>{
      'ok': true,
      'ride_id': rideId,
      'paid': true,
      'connection_fee_minor': paywall['connection_fee_minor'],
    };
  }

  static Map<String, dynamic> getSeats(String rideId) {
    final ride = _rides[rideId];
    if (ride == null) {
      throw ApiException(
        statusCode: 404,
        code: 'ride_not_found',
        message: 'Ride not found in mock store',
        traceId: newRequestId(),
        rawBody: rideId,
      );
    }
    final selected = _selectedSeatsByRide[rideId] ?? <String>[];
    final seats =
        <Map<String, dynamic>>[
              <String, dynamic>{'seat_id': 'FRONT_RIGHT', 'type': 'front'},
              <String, dynamic>{'seat_id': 'BACK_LEFT', 'type': 'window'},
              <String, dynamic>{'seat_id': 'BACK_MIDDLE', 'type': 'middle'},
              <String, dynamic>{'seat_id': 'BACK_RIGHT', 'type': 'window'},
            ]
            .map((item) {
              return <String, dynamic>{
                ...item,
                'selected': selected.contains(item['seat_id']),
                'available': true,
              };
            })
            .toList(growable: false);

    return <String, dynamic>{
      'seats': seats,
      'selected_seat_ids': selected,
      'base_price_minor': ride['base_price_minor'] ?? 7000,
      'charter_mode': ride['charter_mode'] == true,
    };
  }

  static Map<String, dynamic> selectSeats(
    String rideId, {
    required List<String> seatIds,
    required int pricingMinor,
  }) {
    final ride = _rides[rideId];
    if (ride == null) {
      throw ApiException(
        statusCode: 404,
        code: 'ride_not_found',
        message: 'Ride not found in mock store',
        traceId: newRequestId(),
        rawBody: rideId,
      );
    }
    _selectedSeatsByRide[rideId] = seatIds;
    ride['status'] = 'CONFIRMED';
    ride['state'] = 'CONFIRMED';
    ride['pricing_minor'] = pricingMinor;
    return <String, dynamic>{
      'ok': true,
      'ride_id': rideId,
      'seat_ids': seatIds,
      'pricing_minor': pricingMinor,
    };
  }

  static Map<String, dynamic> cancelRide(String rideId) {
    final ride = _rides[rideId];
    if (ride == null) {
      throw ApiException(
        statusCode: 404,
        code: 'ride_not_found',
        message: 'Ride not found in mock store',
        traceId: newRequestId(),
        rawBody: rideId,
      );
    }
    ride['status'] = 'CANCELLED';
    ride['state'] = 'CANCELLED';
    return <String, dynamic>{
      'ok': true,
      'ride_id': rideId,
      'status': 'CANCELLED',
    };
  }

  static Map<String, dynamic> saveRouteChain(Map<String, dynamic> payload) {
    final route = <String, dynamic>{
      'route_id': 'route-${DateTime.now().millisecondsSinceEpoch}-${_seq++}',
      'nodes': payload['nodes'] ?? const <dynamic>[],
      'vehicle_class': payload['vehicle_class']?.toString() ?? 'sedan',
      'capacity': (payload['capacity'] as num?)?.toInt() ?? 4,
    };
    _routeChains.add(route);
    return route;
  }

  static List<Map<String, dynamic>> matchRoutes({
    required String from,
    required String to,
  }) {
    final normalizedFrom = from.toLowerCase().trim();
    final normalizedTo = to.toLowerCase().trim();
    final matched = _routeChains
        .where((route) {
          final nodes = (route['nodes'] as List<dynamic>? ?? const <dynamic>[])
              .whereType<Map>()
              .map(
                (node) => node['name']?.toString().toLowerCase().trim() ?? '',
              )
              .toList(growable: false);
          if (nodes.isEmpty) {
            return false;
          }
          final hasFrom =
              normalizedFrom.isEmpty || nodes.contains(normalizedFrom);
          final hasTo = normalizedTo.isEmpty || nodes.contains(normalizedTo);
          return hasFrom && hasTo;
        })
        .toList(growable: false);
    if (matched.isNotEmpty) {
      return matched;
    }
    return <Map<String, dynamic>>[
      <String, dynamic>{
        'route_id': 'route-sample-1',
        'nodes': <Map<String, String>>[
          <String, String>{'name': from.isEmpty ? 'Lagos' : from},
          <String, String>{'name': 'Ibadan'},
          <String, String>{'name': to.isEmpty ? 'Abuja' : to},
        ],
        'vehicle_class': 'suv',
        'capacity': 4,
      },
    ];
  }
}
