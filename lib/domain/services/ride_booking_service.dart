import 'package:sqflite/sqflite.dart';

import '../../data/sqlite/dao/rides_dao.dart';
import '../models/ride_trip.dart';
import 'ride_booking_guard_service.dart';

class RideBookingService {
  RideBookingService(this.db, {RideBookingGuardService? guardService})
    : _guardService = guardService ?? RideBookingGuardService(db);

  final DatabaseExecutor db;
  final RideBookingGuardService _guardService;

  Future<void> bookRide(RideTrip ride) async {
    final isCrossBorder =
        ride.tripScope == TripScope.crossCountry ||
        ride.tripScope == TripScope.international;
    await _guardService.assertCanBookRide(
      riderUserId: ride.riderId,
      isCrossBorder: isCrossBorder,
    );
    await RidesDao(db).createRide(ride, viaRideBookingService: true);
  }

  Future<void> bookAwaitingConnectionFeeRide({
    required String rideId,
    required String riderId,
    required String driverId,
    required TripScope tripScope,
    required int feeMinor,
    required DateTime bidAcceptedAt,
    required DateTime feeDeadlineAt,
    required DateTime nowUtc,
  }) async {
    final isCrossBorder =
        tripScope == TripScope.crossCountry ||
        tripScope == TripScope.international;
    await _guardService.assertCanBookRide(
      riderUserId: riderId,
      isCrossBorder: isCrossBorder,
    );
    await RidesDao(db).upsertAwaitingConnectionFee(
      rideId: rideId,
      riderId: riderId,
      driverId: driverId,
      tripScope: tripScope.dbValue,
      feeMinor: feeMinor,
      bidAcceptedAtIso: bidAcceptedAt.toUtc().toIso8601String(),
      feeDeadlineAtIso: feeDeadlineAt.toUtc().toIso8601String(),
      nowIso: nowUtc.toUtc().toIso8601String(),
      viaRideBookingService: true,
    );
  }
}
