import '../../domain/models/manifest_entry.dart';

abstract class ManifestRepository {
  Future<void> upsertEntry(ManifestEntry entry);
  Future<List<ManifestEntry>> listRideEntries(String rideId);
}
