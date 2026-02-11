import 'package:flutter_test/flutter_test.dart';
import 'package:hail_o_finance_core/data/sqlite/hailo_database.dart';
import 'package:hail_o_finance_core/domain/models/ride_trip.dart';
import 'package:hail_o_finance_core/domain/services/ride_booking_guard_service.dart';
import 'package:hail_o_finance_core/domain/services/ride_booking_service.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  test(
    'RideBookingService enforces booking guard before creating ride',
    () async {
      final now = DateTime.utc(2026, 3, 4, 9);
      final db = await HailODatabase().open(databasePath: inMemoryDatabasePath);
      addTearDown(db.close);
      final service = RideBookingService(db);

      await db.insert('users', <String, Object?>{
        'id': 'rider_book_1',
        'role': 'rider',
        'created_at': now.toIso8601String(),
        'updated_at': now.toIso8601String(),
      });

      final ride = RideTrip(
        id: 'ride_book_1',
        riderId: 'rider_book_1',
        tripScope: TripScope.intraCity,
        status: 'pending',
        baseFareMinor: 0,
        premiumMarkupMinor: 0,
        charterMode: false,
        dailyRateMinor: 0,
        totalFareMinor: 0,
        connectionFeeMinor: 0,
        connectionFeePaid: false,
        biddingMode: true,
        createdAt: now,
        updatedAt: now,
      );

      expect(
        () => service.bookRide(ride),
        throwsA(
          isA<BookingBlockedException>().having(
            (e) => e.reason,
            'reason',
            BookingBlockedReason.nextOfKinRequired,
          ),
        ),
      );

      await db.insert('next_of_kin', <String, Object?>{
        'user_id': 'rider_book_1',
        'full_name': 'Book Kin',
        'phone': '+234000000111',
        'relationship': 'family',
        'created_at': now.toIso8601String(),
        'updated_at': now.toIso8601String(),
      });

      await service.bookRide(ride);

      final rides = await db.query(
        'rides',
        where: 'id = ?',
        whereArgs: const <Object>['ride_book_1'],
        limit: 1,
      );
      expect(rides.length, 1);
    },
  );
}
