import 'dart:math';

import '../models/latlng.dart';

class GeoDistance {
  static const double _earthRadiusMeters = 6371000.0;

  double haversineMeters(LatLng a, LatLng b) {
    final dLat = _toRad(b.latitude - a.latitude);
    final dLng = _toRad(b.longitude - a.longitude);
    final lat1 = _toRad(a.latitude);
    final lat2 = _toRad(b.latitude);

    final h =
        pow(sin(dLat / 2), 2) + cos(lat1) * cos(lat2) * pow(sin(dLng / 2), 2);
    final c = 2 * atan2(sqrt(h), sqrt(1 - h));
    return _earthRadiusMeters * c;
  }

  double pointToSegmentDistanceMeters({
    required LatLng point,
    required LatLng segmentStart,
    required LatLng segmentEnd,
  }) {
    final x = point.longitude;
    final y = point.latitude;
    final x1 = segmentStart.longitude;
    final y1 = segmentStart.latitude;
    final x2 = segmentEnd.longitude;
    final y2 = segmentEnd.latitude;

    final dx = x2 - x1;
    final dy = y2 - y1;
    if (dx == 0 && dy == 0) {
      return haversineMeters(point, segmentStart);
    }

    final t = ((x - x1) * dx + (y - y1) * dy) / (dx * dx + dy * dy);
    final clampedT = t.clamp(0.0, 1.0);
    final projection = LatLng(
      latitude: y1 + clampedT * dy,
      longitude: x1 + clampedT * dx,
    );
    return haversineMeters(point, projection);
  }

  double pointToPolylineDistanceMeters({
    required LatLng point,
    required List<LatLng> polyline,
  }) {
    if (polyline.isEmpty) {
      return double.infinity;
    }
    if (polyline.length == 1) {
      return haversineMeters(point, polyline.first);
    }

    var minDistance = double.infinity;
    for (var i = 0; i < polyline.length - 1; i += 1) {
      final distance = pointToSegmentDistanceMeters(
        point: point,
        segmentStart: polyline[i],
        segmentEnd: polyline[i + 1],
      );
      if (distance < minDistance) {
        minDistance = distance;
      }
    }
    return minDistance;
  }

  double _toRad(double degrees) => degrees * pi / 180.0;
}
