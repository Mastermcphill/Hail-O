import '../../domain/models/seat.dart';

abstract class SeatRepository {
  Future<void> upsertSeat(Seat seat);
  Future<List<Seat>> listRideSeats(String rideId);
}
