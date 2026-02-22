import 'package:hail_o_finance_core/sqlite_api.dart';

import '../../../domain/models/ride_request_metadata.dart';
import '../table_names.dart';

class RideRequestMetadataDao {
  const RideRequestMetadataDao(this.db);

  final DatabaseExecutor db;

  Future<void> upsert(RideRequestMetadata metadata) async {
    await db.insert(
      TableNames.rideRequestMetadata,
      metadata.toMap(),
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  Future<RideRequestMetadata?> findByRideId(String rideId) async {
    final rows = await db.query(
      TableNames.rideRequestMetadata,
      where: 'ride_id = ?',
      whereArgs: <Object>[rideId],
      limit: 1,
    );
    if (rows.isEmpty) {
      return null;
    }
    return RideRequestMetadata.fromMap(rows.first);
  }
}
