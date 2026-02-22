import '../../../lib/data/sqlite/dao/ride_request_metadata_dao.dart';
import '../../../lib/domain/models/ride_request_metadata.dart';
import 'package:hail_o_finance_core/sqlite_api.dart';

import 'ride_request_metadata_store.dart';

class SqliteRideRequestMetadataStore extends RideRequestMetadataStore {
  const SqliteRideRequestMetadataStore(this.db);

  final DatabaseExecutor db;

  @override
  Future<RideRequestMetadata?> findByRideId(String rideId) {
    return RideRequestMetadataDao(db).findByRideId(rideId);
  }

  @override
  Future<void> upsert(RideRequestMetadata metadata) {
    return RideRequestMetadataDao(db).upsert(metadata);
  }
}
