import 'dart:math' as math;

import '../errors/domain_errors.dart';

class DispatchPricingConfig {
  const DispatchPricingConfig({
    required this.baseFareMinor,
    required this.perKmMinor,
    required this.minimumFareMinor,
    required this.surgeMultiplier,
    required this.avgSpeedKmh,
    required this.currency,
  });

  factory DispatchPricingConfig.fromEnvironment(Map<String, String> env) {
    final baseFareMinor = _readPositiveInt(
      env,
      'DISPATCH_BASE_FARE_MINOR',
      defaultValue: 1000,
    );
    final perKmMinor = _readPositiveInt(
      env,
      'DISPATCH_PER_KM_MINOR',
      defaultValue: 250,
    );
    final minimumFareMinor = _readPositiveInt(
      env,
      'DISPATCH_MIN_FARE_MINOR',
      defaultValue: 1500,
    );
    final surgeMultiplier = _readPositiveDouble(
      env,
      'DISPATCH_SURGE_MULTIPLIER',
      defaultValue: 1.0,
    );
    final avgSpeedKmh = _readPositiveDouble(
      env,
      'DISPATCH_AVG_SPEED_KMH',
      defaultValue: 25.0,
    );
    final currency = (env['DISPATCH_CURRENCY'] ?? 'NGN').trim().toUpperCase();
    return DispatchPricingConfig(
      baseFareMinor: baseFareMinor,
      perKmMinor: perKmMinor,
      minimumFareMinor: minimumFareMinor,
      surgeMultiplier: surgeMultiplier,
      avgSpeedKmh: avgSpeedKmh,
      currency: currency.isEmpty ? 'NGN' : currency,
    );
  }

  final int baseFareMinor;
  final int perKmMinor;
  final int minimumFareMinor;
  final double surgeMultiplier;
  final double avgSpeedKmh;
  final String currency;

  static int _readPositiveInt(
    Map<String, String> env,
    String key, {
    required int defaultValue,
  }) {
    final parsed = int.tryParse((env[key] ?? '').trim());
    if (parsed == null || parsed <= 0) {
      return defaultValue;
    }
    return parsed;
  }

  static double _readPositiveDouble(
    Map<String, String> env,
    String key, {
    required double defaultValue,
  }) {
    final parsed = double.tryParse((env[key] ?? '').trim());
    if (parsed == null || parsed <= 0 || parsed.isNaN || parsed.isInfinite) {
      return defaultValue;
    }
    return parsed;
  }
}

class DispatchPricingService {
  const DispatchPricingService({required DispatchPricingConfig config})
    : _config = config;

  final DispatchPricingConfig _config;

  static const double _earthRadiusKm = 6371.0088;
  static const double _degToRad = math.pi / 180.0;

  Map<String, Object?> quoteFromPayload(Map<String, Object?> payload) {
    final pickupRaw = _asObjectMap(payload['pickup']);
    final dropoffRaw = _asObjectMap(payload['dropoff']);
    if (pickupRaw == null) {
      throw const DomainInvariantError(code: 'pickup_required');
    }
    if (dropoffRaw == null) {
      throw const DomainInvariantError(code: 'dropoff_required');
    }

    final pickupLat = _readCoordinate(
      pickupRaw['lat'],
      codeIfMissing: 'pickup_lat_required',
      codeIfInvalid: 'invalid_pickup_lat',
      min: -90,
      max: 90,
    );
    final pickupLng = _readCoordinate(
      pickupRaw['lng'],
      codeIfMissing: 'pickup_lng_required',
      codeIfInvalid: 'invalid_pickup_lng',
      min: -180,
      max: 180,
    );
    final dropoffLat = _readCoordinate(
      dropoffRaw['lat'],
      codeIfMissing: 'dropoff_lat_required',
      codeIfInvalid: 'invalid_dropoff_lat',
      min: -90,
      max: 90,
    );
    final dropoffLng = _readCoordinate(
      dropoffRaw['lng'],
      codeIfMissing: 'dropoff_lng_required',
      codeIfInvalid: 'invalid_dropoff_lng',
      min: -180,
      max: 180,
    );

    final serviceLevel = _parseServiceLevel(payload['service_level']);
    final distanceKm = _haversineKm(
      startLat: pickupLat,
      startLng: pickupLng,
      endLat: dropoffLat,
      endLng: dropoffLng,
    );
    final distanceRounded = _round3(distanceKm);
    final durationMinEstimate = _estimateDurationMin(distanceKm);
    final distanceChargeMinor = (distanceKm * _config.perKmMinor).round();
    final preSurgeMinor = _config.baseFareMinor + distanceChargeMinor;
    final surgedMinor = (preSurgeMinor * _config.surgeMultiplier).round();
    final minimumFareApplied = surgedMinor < _config.minimumFareMinor;
    final priceMinor = minimumFareApplied
        ? _config.minimumFareMinor
        : surgedMinor;

    return <String, Object?>{
      'distance_km': distanceRounded,
      'duration_min_est': durationMinEstimate,
      'price_minor': priceMinor,
      'currency': _config.currency,
      'breakdown': <String, Object?>{
        'service_level': serviceLevel,
        'base_fare_minor': _config.baseFareMinor,
        'per_km_minor': _config.perKmMinor,
        'distance_charge_minor': distanceChargeMinor,
        'surge_multiplier': _config.surgeMultiplier,
        'surged_subtotal_minor': surgedMinor,
        'minimum_fare_minor': _config.minimumFareMinor,
        'minimum_fare_applied': minimumFareApplied,
      },
    };
  }

  Map<Object?, Object?>? _asObjectMap(Object? value) {
    if (value is Map<Object?, Object?>) {
      return value;
    }
    if (value is Map) {
      return Map<Object?, Object?>.from(value);
    }
    return null;
  }

  double _readCoordinate(
    Object? rawValue, {
    required String codeIfMissing,
    required String codeIfInvalid,
    required double min,
    required double max,
  }) {
    if (rawValue == null) {
      throw DomainInvariantError(code: codeIfMissing);
    }
    final value = _parseDouble(rawValue);
    if (value == null || value.isNaN || value.isInfinite) {
      throw DomainInvariantError(code: codeIfInvalid);
    }
    if (value < min || value > max) {
      throw DomainInvariantError(code: codeIfInvalid);
    }
    return value;
  }

  String _parseServiceLevel(Object? raw) {
    if (raw == null) {
      return 'standard';
    }
    if (raw is! String) {
      throw const DomainInvariantError(code: 'invalid_service_level');
    }
    final normalized = raw.trim().toLowerCase();
    if (normalized.isEmpty) {
      return 'standard';
    }
    return normalized;
  }

  double _haversineKm({
    required double startLat,
    required double startLng,
    required double endLat,
    required double endLng,
  }) {
    final latDelta = (endLat - startLat) * _degToRad;
    final lngDelta = (endLng - startLng) * _degToRad;
    final lat1 = startLat * _degToRad;
    final lat2 = endLat * _degToRad;

    final sinLat = math.sin(latDelta / 2);
    final sinLng = math.sin(lngDelta / 2);
    final a =
        (sinLat * sinLat) + (math.cos(lat1) * math.cos(lat2) * sinLng * sinLng);
    final normalizedA = a < 0
        ? 0
        : a > 1
        ? 1
        : a;
    final c =
        2 * math.atan2(math.sqrt(normalizedA), math.sqrt(1 - normalizedA));
    return _earthRadiusKm * c;
  }

  int _estimateDurationMin(double distanceKm) {
    if (distanceKm <= 0) {
      return 0;
    }
    final durationMinutes = (distanceKm / _config.avgSpeedKmh) * 60;
    return durationMinutes.ceil();
  }

  double? _parseDouble(Object? rawValue) {
    if (rawValue is num) {
      return rawValue.toDouble();
    }
    if (rawValue is String) {
      return double.tryParse(rawValue.trim());
    }
    return null;
  }

  double _round3(double value) {
    return double.parse(value.toStringAsFixed(3));
  }
}
