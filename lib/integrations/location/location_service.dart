import 'dart:async';

import 'package:geolocator/geolocator.dart' as geo;

import '../../domain/models/latlng.dart';

class LocationService {
  const LocationService();

  Future<LatLng?> getCurrentPosition() async {
    final allowed = await _hasUsablePermission();
    if (!allowed) {
      return null;
    }
    try {
      final position = await geo.Geolocator.getCurrentPosition(
        locationSettings: const geo.LocationSettings(
          accuracy: geo.LocationAccuracy.high,
        ),
      );
      return LatLng(latitude: position.latitude, longitude: position.longitude);
    } catch (_) {
      return null;
    }
  }

  Stream<LatLng> positionStream({
    geo.LocationAccuracy accuracy = geo.LocationAccuracy.high,
    Duration interval = const Duration(seconds: 5),
  }) async* {
    final allowed = await _hasUsablePermission();
    if (!allowed) {
      return;
    }

    final settings = geo.LocationSettings(accuracy: accuracy);
    DateTime? lastEmitAt;
    await for (final position in geo.Geolocator.getPositionStream(
      locationSettings: settings,
    )) {
      final now = DateTime.now().toUtc();
      if (lastEmitAt == null || now.difference(lastEmitAt) >= interval) {
        lastEmitAt = now;
        yield LatLng(
          latitude: position.latitude,
          longitude: position.longitude,
        );
      }
    }
  }

  Future<bool> _hasUsablePermission() async {
    final serviceEnabled = await geo.Geolocator.isLocationServiceEnabled();
    if (!serviceEnabled) {
      return false;
    }

    var permission = await geo.Geolocator.checkPermission();
    if (permission == geo.LocationPermission.denied) {
      permission = await geo.Geolocator.requestPermission();
    }
    return permission == geo.LocationPermission.always ||
        permission == geo.LocationPermission.whileInUse;
  }
}
