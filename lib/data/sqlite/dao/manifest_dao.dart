import 'package:hail_o_finance_core/sqlite_api.dart';

import '../../../domain/models/manifest_entry.dart';
import '../table_names.dart';

class ManifestDao {
  const ManifestDao(this.db);

  final Database db;

  Future<void> upsert(ManifestEntry entry) async {
    await db.insert(
      TableNames.manifests,
      entry.toMap(),
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  Future<List<ManifestEntry>> listByRide(String rideId) async {
    final rows = await db.query(
      TableNames.manifests,
      where: 'ride_id = ?',
      whereArgs: <Object>[rideId],
      orderBy: 'created_at ASC',
    );
    return rows.map(ManifestEntry.fromMap).toList(growable: false);
  }
}
