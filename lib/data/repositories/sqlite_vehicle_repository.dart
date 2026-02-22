import '../../domain/models/vehicle.dart';
import '../sqlite/dao/vehicles_dao.dart';
import 'vehicle_repository.dart';

class SqliteVehicleRepository implements VehicleRepository {
  const SqliteVehicleRepository(this._dao);

  final VehiclesDao _dao;

  @override
  Future<Vehicle?> getVehicle(String vehicleId) => _dao.findById(vehicleId);

  @override
  Future<List<Vehicle>> listDriverVehicles(String driverId) {
    return _dao.listByDriver(driverId);
  }

  @override
  Future<void> upsertVehicle(Vehicle vehicle) => _dao.upsert(vehicle);
}
