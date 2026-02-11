import 'package:sqflite/sqflite.dart';

import '../../data/sqlite/dao/rides_dao.dart';
import '../models/ride_trip.dart';
import 'ride_booking_guard_service.dart';

class RideBookingService {
  RideBookingService(this.db, {RideBookingGuardService? guardService})
    : _guardService = guardService ?? RideBookingGuardService(db);

  final Database db;
  final RideBookingGuardService _guardService;

  Future<void> bookRide(RideTrip ride) async {
    final isCrossBorder =
        ride.tripScope == TripScope.crossCountry ||
        ride.tripScope == TripScope.international;
    await _guardService.assertCanBookRide(
      riderUserId: ride.riderId,
      isCrossBorder: isCrossBorder,
    );
    await RidesDao(db).createRide(ride);
  }
}
