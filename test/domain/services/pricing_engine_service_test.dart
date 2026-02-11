import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:hail_o_finance_core/data/sqlite/hailo_database.dart';
import 'package:hail_o_finance_core/domain/models/ride_trip.dart';
import 'package:hail_o_finance_core/domain/services/pricing_engine_service.dart';
import 'package:hail_o_finance_core/domain/services/ride_booking_service.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  test('pricing quote is deterministic for same inputs', () {
    const service = PricingEngineService();
    final requestedAt = DateTime.utc(2026, 2, 11, 12, 0);

    final first = service.quote(
      tripScope: 'inter_state',
      distanceMeters: 52340,
      durationSeconds: 7490,
      luggageCount: 3,
      vehicleClass: PricingVehicleClass.suv,
      requestedAtUtc: requestedAt,
    );
    final second = service.quote(
      tripScope: 'inter_state',
      distanceMeters: 52340,
      durationSeconds: 7490,
      luggageCount: 3,
      vehicleClass: PricingVehicleClass.suv,
      requestedAtUtc: requestedAt,
    );

    expect(second.fareMinor, first.fareMinor);
    expect(second.ruleVersion, first.ruleVersion);
    expect(second.breakdownJson, first.breakdownJson);

    final decoded = jsonDecode(first.breakdownJson) as Map<String, dynamic>;
    expect(decoded['fare_minor'], first.fareMinor);
    expect(decoded['rule_version'], first.ruleVersion);
  });

  test(
    'bookRideWithPricing persists pricing snapshot on rides table',
    () async {
      final now = DateTime.utc(2026, 2, 11, 12, 0);
      final db = await HailODatabase().open(databasePath: inMemoryDatabasePath);
      addTearDown(db.close);

      await db.insert('users', <String, Object?>{
        'id': 'rider_pricing_1',
        'role': 'rider',
        'created_at': now.toIso8601String(),
        'updated_at': now.toIso8601String(),
      });
      await db.insert('next_of_kin', <String, Object?>{
        'user_id': 'rider_pricing_1',
        'full_name': 'Pricing Kin',
        'phone': '+234000000300',
        'relationship': 'friend',
        'created_at': now.toIso8601String(),
        'updated_at': now.toIso8601String(),
      });

      final booking = RideBookingService(db);
      final inputRide = RideTrip(
        id: 'ride_pricing_1',
        riderId: 'rider_pricing_1',
        tripScope: TripScope.intraCity,
        status: 'pending',
        biddingMode: true,
        baseFareMinor: 0,
        premiumMarkupMinor: 0,
        charterMode: false,
        dailyRateMinor: 0,
        totalFareMinor: 0,
        connectionFeeMinor: 0,
        connectionFeePaid: false,
        createdAt: now,
        updatedAt: now,
      );

      final booked = await booking.bookRideWithPricing(
        ride: inputRide,
        distanceMeters: 10000,
        durationSeconds: 1200,
        luggageCount: 1,
        vehicleClass: PricingVehicleClass.sedan,
        requestedAtUtc: now,
      );

      final rows = await db.query(
        'rides',
        where: 'id = ?',
        whereArgs: const <Object>['ride_pricing_1'],
        limit: 1,
      );
      expect(rows.length, 1);

      final row = rows.first;
      expect(row['pricing_version'], booked.pricingVersion);
      expect(row['quoted_fare_minor'], booked.quotedFareMinor);
      expect(row['total_fare_minor'], booked.totalFareMinor);

      final storedBreakdown = row['pricing_breakdown_json'] as String;
      final breakdown = jsonDecode(storedBreakdown) as Map<String, dynamic>;
      expect(breakdown['fare_minor'], booked.quotedFareMinor);
    },
  );
}
