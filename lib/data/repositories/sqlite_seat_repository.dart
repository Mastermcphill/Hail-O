import '../../domain/models/seat.dart';
import '../sqlite/dao/seats_dao.dart';
import 'seat_repository.dart';

class SqliteSeatRepository implements SeatRepository {
  const SqliteSeatRepository(this._dao);

  final SeatsDao _dao;

  @override
  Future<List<Seat>> listRideSeats(String rideId) => _dao.listByRide(rideId);

  @override
  Future<void> upsertSeat(Seat seat) => _dao.upsert(seat);
}
