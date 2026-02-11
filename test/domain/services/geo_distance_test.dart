import 'package:flutter_test/flutter_test.dart';
import 'package:hail_o_finance_core/domain/models/latlng.dart';
import 'package:hail_o_finance_core/domain/services/geo_distance.dart';

void main() {
  test('haversine sanity check for short distance', () {
    final geo = GeoDistance();
    final a = LatLng(latitude: 6.5244, longitude: 3.3792);
    final b = LatLng(latitude: 6.5249, longitude: 3.3802);
    final distance = geo.haversineMeters(a, b);
    expect(distance, greaterThan(100));
    expect(distance, lessThan(150));
  });

  test('point to polyline distance is zero-ish on segment', () {
    final geo = GeoDistance();
    final line = <LatLng>[
      const LatLng(latitude: 6.5244, longitude: 3.3792),
      const LatLng(latitude: 6.5244, longitude: 3.3892),
    ];
    final pointOnLine = const LatLng(latitude: 6.5244, longitude: 3.3842);
    final distance = geo.pointToPolylineDistanceMeters(
      point: pointOnLine,
      polyline: line,
    );
    expect(distance, lessThan(2));
  });
}
