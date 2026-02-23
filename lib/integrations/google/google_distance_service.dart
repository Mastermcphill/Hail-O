import 'dart:convert';

import 'package:http/http.dart' as http;

class DistanceEstimate {
  const DistanceEstimate({
    required this.distanceMeters,
    required this.durationSeconds,
    required this.source,
  });

  final int distanceMeters;
  final int durationSeconds;
  final String source;
}

class GoogleDistanceService {
  GoogleDistanceService({http.Client? httpClient, String? apiKey})
    : _httpClient = httpClient ?? http.Client(),
      _apiKey =
          apiKey ?? const String.fromEnvironment('GOOGLE_DISTANCE_MATRIX_KEY');

  final http.Client _httpClient;
  final String _apiKey;

  Future<DistanceEstimate> estimate({
    required String origin,
    required String destination,
  }) async {
    final cleanOrigin = origin.trim();
    final cleanDestination = destination.trim();
    if (cleanOrigin.isEmpty || cleanDestination.isEmpty) {
      return _stubEstimate(cleanOrigin, cleanDestination, source: 'stub:empty');
    }

    if (_apiKey.trim().isEmpty) {
      return _stubEstimate(
        cleanOrigin,
        cleanDestination,
        source: 'stub:no_key',
      );
    }

    final uri =
        Uri.https('maps.googleapis.com', '/maps/api/distancematrix/json', {
          'origins': cleanOrigin,
          'destinations': cleanDestination,
          'key': _apiKey,
          'units': 'metric',
          'mode': 'driving',
        });

    try {
      final response = await _httpClient.get(uri);
      if (response.statusCode >= 400) {
        return _stubEstimate(
          cleanOrigin,
          cleanDestination,
          source: 'stub:http_${response.statusCode}',
        );
      }
      final decoded = jsonDecode(response.body);
      if (decoded is! Map) {
        return _stubEstimate(
          cleanOrigin,
          cleanDestination,
          source: 'stub:parse',
        );
      }

      final rows = decoded['rows'];
      if (rows is! List || rows.isEmpty) {
        return _stubEstimate(
          cleanOrigin,
          cleanDestination,
          source: 'stub:rows',
        );
      }
      final firstRow = rows.first;
      if (firstRow is! Map) {
        return _stubEstimate(cleanOrigin, cleanDestination, source: 'stub:row');
      }

      final elements = firstRow['elements'];
      if (elements is! List || elements.isEmpty) {
        return _stubEstimate(
          cleanOrigin,
          cleanDestination,
          source: 'stub:elements',
        );
      }
      final firstElement = elements.first;
      if (firstElement is! Map) {
        return _stubEstimate(
          cleanOrigin,
          cleanDestination,
          source: 'stub:element',
        );
      }

      final status = (firstElement['status'] ?? '').toString();
      if (status != 'OK') {
        return _stubEstimate(
          cleanOrigin,
          cleanDestination,
          source: 'stub:status_$status',
        );
      }

      final distanceValue =
          ((firstElement['distance'] as Map?)?['value'] as num?)?.toInt() ?? 0;
      final durationValue =
          ((firstElement['duration'] as Map?)?['value'] as num?)?.toInt() ?? 0;
      if (distanceValue <= 0 || durationValue <= 0) {
        return _stubEstimate(
          cleanOrigin,
          cleanDestination,
          source: 'stub:zero',
        );
      }

      return DistanceEstimate(
        distanceMeters: distanceValue,
        durationSeconds: durationValue,
        source: 'google',
      );
    } catch (_) {
      return _stubEstimate(cleanOrigin, cleanDestination, source: 'stub:error');
    }
  }

  DistanceEstimate _stubEstimate(
    String origin,
    String destination, {
    required String source,
  }) {
    final combined = (origin + destination).replaceAll(RegExp(r'\s+'), '');
    final seed = combined.isEmpty ? 12 : combined.length;
    final distanceMeters = (seed * 900).clamp(4000, 60000);
    final durationSeconds = ((distanceMeters / 8.5).round()).clamp(900, 10800);
    return DistanceEstimate(
      distanceMeters: distanceMeters,
      durationSeconds: durationSeconds,
      source: source,
    );
  }
}
