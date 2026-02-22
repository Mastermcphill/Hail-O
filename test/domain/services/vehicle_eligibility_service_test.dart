import 'package:flutter_test/flutter_test.dart';
import 'package:hail_o_finance_core/domain/models/vehicle.dart';
import 'package:hail_o_finance_core/domain/services/vehicle_eligibility_service.dart';

void main() {
  test('luggage=3 excludes sedan/hatchback and allows suv/bus', () {
    const service = VehicleEligibilityService();
    expect(service.isEligible(type: VehicleType.sedan, luggageCount: 3), false);
    expect(
      service.isEligible(type: VehicleType.hatchback, luggageCount: 3),
      false,
    );
    expect(service.isEligible(type: VehicleType.suv, luggageCount: 3), true);
    expect(service.isEligible(type: VehicleType.bus, luggageCount: 3), true);
  });

  test('luggage=2 allows all vehicle types', () {
    const service = VehicleEligibilityService();
    for (final type in VehicleType.values) {
      expect(service.isEligible(type: type, luggageCount: 2), true);
    }
  });
}
