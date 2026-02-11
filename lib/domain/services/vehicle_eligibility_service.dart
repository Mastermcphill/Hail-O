import '../models/vehicle.dart';

class VehicleEligibilityService {
  const VehicleEligibilityService();

  bool isEligible({required VehicleType type, required int luggageCount}) {
    if (luggageCount <= 2) {
      return true;
    }
    return type == VehicleType.suv || type == VehicleType.bus;
  }
}
