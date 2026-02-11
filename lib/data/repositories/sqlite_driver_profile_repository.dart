import '../../domain/models/driver_profile.dart';
import '../sqlite/dao/driver_profiles_dao.dart';
import 'driver_profile_repository.dart';

class SqliteDriverProfileRepository implements DriverProfileRepository {
  const SqliteDriverProfileRepository(this._dao);

  final DriverProfilesDao _dao;

  @override
  Future<DriverProfile?> getProfile(String driverId) {
    return _dao.findByDriverId(driverId);
  }

  @override
  Future<void> upsertProfile(DriverProfile profile) => _dao.upsert(profile);
}
