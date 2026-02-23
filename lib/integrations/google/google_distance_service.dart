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
  GoogleDistanceService({http.Client? client})
    : _client = client ?? http.Client();

  static const _distanceMatrixKey = String.fromEnvironment(
    'GOOGLE_DISTANCE_MATRIX_API_KEY',
  );

  final http.Client _client;

  bool get isConfigured => _distanceMatrixKey.trim().isNotEmpty;

  Future<DistanceEstimate> estimate({
    required String origin,
    required String destination,
  }) async {
    if (!isConfigured) {
      return _stubEstimate();
    }

    final uri = Uri.https(
      'maps.googleapis.com',
      '/maps/api/distancematrix/json',
      <String, String>{
        'origins': origin,
        'destinations': destination,
        'mode': 'driving',
        'key': _distanceMatrixKey,
      },
    );

    try {
      final response = await _client.get(uri);
      if (response.statusCode != 200) {
        return _stubEstimate();
      }
      final decoded = jsonDecode(response.body);
      if (decoded is! Map<String, dynamic>) {
        return _stubEstimate();
      }
      final rows = decoded['rows'];
      if (rows is! List || rows.isEmpty) {
        return _stubEstimate();
      }
      final firstRow = rows.first;
      if (firstRow is! Map<String, dynamic>) {
        return _stubEstimate();
      }
      final elements = firstRow['elements'];
      if (elements is! List || elements.isEmpty) {
        return _stubEstimate();
      }
      final firstElement = elements.first;
      if (firstElement is! Map<String, dynamic>) {
        return _stubEstimate();
      }
      final distance = firstElement['distance'];
      final duration = firstElement['duration'];
      if (distance is! Map || duration is! Map) {
        return _stubEstimate();
      }
      final distanceMeters = (distance['value'] as num?)?.toInt();
      final durationSeconds = (duration['value'] as num?)?.toInt();
      if (distanceMeters == null || durationSeconds == null) {
        return _stubEstimate();
      }
      return DistanceEstimate(
        distanceMeters: distanceMeters,
        durationSeconds: durationSeconds,
        source: 'google_distance_matrix',
      );
    } catch (_) {
      return _stubEstimate();
    }
  }

  DistanceEstimate _stubEstimate() {
    return const DistanceEstimate(
      distanceMeters: 12000,
      durationSeconds: 1800,
      source: 'stub',
    );
  }
}
