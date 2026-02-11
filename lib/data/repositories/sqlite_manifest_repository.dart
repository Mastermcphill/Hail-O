import '../../domain/models/manifest_entry.dart';
import '../sqlite/dao/manifest_dao.dart';
import 'manifest_repository.dart';

class SqliteManifestRepository implements ManifestRepository {
  const SqliteManifestRepository(this._dao);

  final ManifestDao _dao;

  @override
  Future<List<ManifestEntry>> listRideEntries(String rideId) =>
      _dao.listByRide(rideId);

  @override
  Future<void> upsertEntry(ManifestEntry entry) => _dao.upsert(entry);
}
