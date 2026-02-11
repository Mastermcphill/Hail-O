import '../../domain/models/vehicle.dart';

abstract class VehicleRepository {
  Future<void> upsertVehicle(Vehicle vehicle);
  Future<Vehicle?> getVehicle(String vehicleId);
  Future<List<Vehicle>> listDriverVehicles(String driverId);
}
