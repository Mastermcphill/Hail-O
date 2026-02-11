import 'dart:convert';

import '../models/pricing_quote.dart';

enum PricingVehicleClass {
  sedan('sedan'),
  hatchback('hatchback'),
  suv('suv'),
  bus('bus');

  const PricingVehicleClass(this.dbValue);
  final String dbValue;

  static PricingVehicleClass fromDbValue(String value) {
    return PricingVehicleClass.values.firstWhere(
      (vehicleClass) => vehicleClass.dbValue == value,
      orElse: () => PricingVehicleClass.sedan,
    );
  }
}

class PricingEngineService {
  const PricingEngineService({this.ruleVersion = 'pricing_v1'});

  final String ruleVersion;

  PricingQuote quote({
    required String tripScope,
    required int distanceMeters,
    required int durationSeconds,
    required int luggageCount,
    required PricingVehicleClass vehicleClass,
    required DateTime requestedAtUtc,
  }) {
    final scope = tripScope.trim().toLowerCase();
    final distanceKm = distanceMeters < 0 ? 0 : distanceMeters ~/ 1000;
    final durationMinutes = durationSeconds < 0 ? 0 : durationSeconds ~/ 60;

    final baseFareMinor = _baseFareMinor(scope);
    final distanceComponentMinor = distanceKm * _distanceRatePerKmMinor(scope);
    final timeComponentMinor = durationMinutes * _timeRatePerMinuteMinor(scope);
    final luggageSurchargeMinor = luggageCount > 2
        ? (luggageCount - 2) * 2000
        : 0;

    var subtotalMinor =
        baseFareMinor +
        distanceComponentMinor +
        timeComponentMinor +
        luggageSurchargeMinor;
    subtotalMinor = _applyVehicleMultiplier(subtotalMinor, vehicleClass);
    final surgePercent = _surgePercentForTime(requestedAtUtc.toUtc());
    final surgeMinor = (subtotalMinor * surgePercent) ~/ 100;
    final fareMinor = subtotalMinor + surgeMinor;

    final breakdown = <String, Object?>{
      'rule_version': ruleVersion,
      'trip_scope': scope,
      'distance_meters': distanceMeters,
      'duration_seconds': durationSeconds,
      'distance_km_rounded': distanceKm,
      'duration_min_rounded': durationMinutes,
      'vehicle_class': vehicleClass.dbValue,
      'base_fare_minor': baseFareMinor,
      'distance_component_minor': distanceComponentMinor,
      'time_component_minor': timeComponentMinor,
      'luggage_surcharge_minor': luggageSurchargeMinor,
      'surge_percent': surgePercent,
      'surge_minor': surgeMinor,
      'fare_minor': fareMinor,
    };

    return PricingQuote(
      fareMinor: fareMinor,
      ruleVersion: ruleVersion,
      breakdownJson: jsonEncode(breakdown),
    );
  }

  int _baseFareMinor(String scope) {
    if (scope == 'international') {
      return 120000;
    }
    if (scope == 'cross_country') {
      return 70000;
    }
    if (scope == 'inter_state') {
      return 40000;
    }
    return 15000;
  }

  int _distanceRatePerKmMinor(String scope) {
    if (scope == 'international') {
      return 9000;
    }
    if (scope == 'cross_country') {
      return 7000;
    }
    if (scope == 'inter_state') {
      return 5000;
    }
    return 2000;
  }

  int _timeRatePerMinuteMinor(String scope) {
    if (scope == 'international') {
      return 500;
    }
    if (scope == 'cross_country') {
      return 400;
    }
    if (scope == 'inter_state') {
      return 300;
    }
    return 150;
  }

  int _applyVehicleMultiplier(
    int subtotalMinor,
    PricingVehicleClass vehicleClass,
  ) {
    final percent = switch (vehicleClass) {
      PricingVehicleClass.sedan => 100,
      PricingVehicleClass.hatchback => 95,
      PricingVehicleClass.suv => 120,
      PricingVehicleClass.bus => 150,
    };
    return (subtotalMinor * percent) ~/ 100;
  }

  int _surgePercentForTime(DateTime requestedAtUtc) {
    final hour = requestedAtUtc.hour;
    if ((hour >= 7 && hour <= 10) || (hour >= 17 && hour <= 20)) {
      return 10;
    }
    return 0;
  }
}
