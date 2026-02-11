import 'package:sqflite/sqflite.dart';

import '../../../domain/models/ride_trip.dart';

class RidesDao {
  const RidesDao(this.db);

  final DatabaseExecutor db;

  /// Creates a booked ride row.
  ///
  /// Do not call this directly from app/service code. Use
  /// `RideBookingService.bookRide(...)` so booking guard invariants are
  /// enforced.
  Future<void> createRide(
    RideTrip ride, {
    required bool viaRideBookingService,
  }) async {
    if (!viaRideBookingService) {
      throw ArgumentError(
        'RidesDao.createRide must be called via RideBookingService.',
      );
    }
    await db.insert(
      'rides',
      ride.toMap(),
      conflictAlgorithm: ConflictAlgorithm.abort,
    );
  }

  /// Upserts an accepted-bid ride awaiting connection fee payment.
  ///
  /// Do not call this directly from app/service code. Use
  /// `RideBookingService.bookAwaitingConnectionFeeRide(...)` so booking guard
  /// invariants are enforced.
  Future<void> upsertAwaitingConnectionFee({
    required String rideId,
    required String riderId,
    required String driverId,
    required String tripScope,
    required int feeMinor,
    required String bidAcceptedAtIso,
    required String feeDeadlineAtIso,
    required String nowIso,
    required bool viaRideBookingService,
  }) async {
    if (!viaRideBookingService) {
      throw ArgumentError(
        'RidesDao.upsertAwaitingConnectionFee must be called via RideBookingService.',
      );
    }
    await db.insert('rides', <String, Object?>{
      'id': rideId,
      'rider_id': riderId,
      'driver_id': driverId,
      'status': 'awaiting_connection_fee',
      'base_fare_minor': 0,
      'premium_markup_minor': 0,
      'trip_scope': tripScope,
      'connection_fee_minor': feeMinor,
      'bid_accepted_at': bidAcceptedAtIso,
      'connection_fee_deadline_at': feeDeadlineAtIso,
      'connection_fee_paid_at': null,
      'cancelled_at': null,
      'created_at': nowIso,
      'updated_at': nowIso,
    }, conflictAlgorithm: ConflictAlgorithm.replace);
  }

  Future<Map<String, Object?>?> findById(String rideId) async {
    final rows = await db.query(
      'rides',
      where: 'id = ?',
      whereArgs: <Object>[rideId],
      limit: 1,
    );
    if (rows.isEmpty) {
      return null;
    }
    return Map<String, Object?>.from(rows.first);
  }

  Future<List<Map<String, Object?>>>
  listAwaitingConnectionFeeWithoutPayment() async {
    final rows = await db.query(
      'rides',
      columns: <String>['id', 'connection_fee_deadline_at'],
      where: 'status = ? AND connection_fee_paid_at IS NULL',
      whereArgs: const <Object>['awaiting_connection_fee'],
    );
    return rows
        .map((row) => Map<String, Object?>.from(row))
        .toList(growable: false);
  }

  /// Marks an already-booked ride as cancelled.
  ///
  /// Do not call this directly from business flows. Use
  /// `CancelRideService.collectCancellationPenalty(...)` so penalty, ledger,
  /// and idempotency invariants are enforced before status mutation.
  Future<void> markCancelled({
    required String rideId,
    required String nowIso,
    required bool viaCancelRideService,
  }) async {
    if (!viaCancelRideService) {
      throw ArgumentError(
        'RidesDao.markCancelled must be called via CancelRideService.',
      );
    }
    await db.update(
      'rides',
      <String, Object?>{
        'status': 'cancelled',
        'cancelled_at': nowIso,
        'updated_at': nowIso,
      },
      where: 'id = ?',
      whereArgs: <Object>[rideId],
    );
  }

  Future<void> markConnectionFeePaid({
    required String rideId,
    required String nowIso,
  }) async {
    await db.update(
      'rides',
      <String, Object?>{
        'status': 'connection_fee_paid',
        'connection_fee_paid_at': nowIso,
        'updated_at': nowIso,
      },
      where: 'id = ?',
      whereArgs: <Object>[rideId],
    );
  }

  Future<void> updateFinanceIfExists({
    required String rideId,
    required int baseFareMinor,
    required int premiumSeatMarkupMinor,
    required String nowIso,
  }) async {
    final existing = await findById(rideId);
    if (existing == null) {
      return;
    }
    await db.update(
      'rides',
      <String, Object?>{
        'status': 'finance_settled',
        'base_fare_minor': baseFareMinor,
        'premium_markup_minor': premiumSeatMarkupMinor,
        'updated_at': nowIso,
      },
      where: 'id = ?',
      whereArgs: <Object>[rideId],
    );
  }
}
