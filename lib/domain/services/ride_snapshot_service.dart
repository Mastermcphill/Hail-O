import 'package:hail_o_finance_core/sqlite_api.dart';

import '../../data/sqlite/dao/disputes_dao.dart';
import '../../data/sqlite/dao/escrow_holds_dao.dart';
import '../../data/sqlite/dao/payout_records_dao.dart';
import '../../data/sqlite/dao/penalty_records_dao.dart';
import '../../data/sqlite/dao/ride_events_dao.dart';
import '../../data/sqlite/dao/rides_dao.dart';
import '../../data/sqlite/dao/ride_request_metadata_dao.dart';

class RideSnapshotService {
  const RideSnapshotService(this.db);

  final DatabaseExecutor db;

  Future<Map<String, Object?>> getRideSnapshot(String rideId) async {
    final ride = await RidesDao(db).findById(rideId);
    if (ride == null) {
      return <String, Object?>{'ok': false, 'error': 'ride_not_found'};
    }

    final metadata = await RideRequestMetadataDao(db).findByRideId(rideId);
    final escrow = await EscrowHoldsDao(db).findByRideId(rideId);
    final payout = await PayoutRecordsDao(db).findLatestByRideId(rideId);
    final disputes = await DisputesDao(db).listByRideId(rideId);
    final penalties = await PenaltyRecordsDao(db).listByRideId(rideId);
    final events = await RideEventsDao(db).listByRideId(rideId);

    return <String, Object?>{
      'ok': true,
      'ride': ride,
      'scheduled_departure_at': metadata?.scheduledDepartureAt
          .toUtc()
          .toIso8601String(),
      'escrow': escrow?.toMap(),
      'payout': payout?.toMap(),
      'disputes': disputes.map((item) => item.toMap()).toList(growable: false),
      'penalties': penalties
          .map((item) => item.toMap())
          .toList(growable: false),
      'events': events.map((item) => item.toMap()).toList(growable: false),
    };
  }
}
