import '../../domain/models/driver_profile.dart';

abstract class DriverProfileRepository {
  Future<void> upsertProfile(DriverProfile profile);
  Future<DriverProfile?> getProfile(String driverId);
}
