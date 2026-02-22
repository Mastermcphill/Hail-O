import 'package:flutter_test/flutter_test.dart';
import 'package:hail_o_finance_core/data/sqlite/hailo_database.dart';
import 'package:hail_o_finance_core/domain/services/ride_booking_guard_service.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  group('RideBookingGuardService', () {
    test('missing NextOfKin blocks booking', () async {
      final now = DateTime.utc(2026, 3, 2, 8);
      final db = await HailODatabase().open(databasePath: inMemoryDatabasePath);
      addTearDown(db.close);
      final service = RideBookingGuardService(db);

      await db.insert('users', <String, Object?>{
        'id': 'rider_guard_1',
        'role': 'rider',
        'created_at': now.toIso8601String(),
        'updated_at': now.toIso8601String(),
      });

      expect(
        () => service.assertCanBookRide(
          riderUserId: 'rider_guard_1',
          isCrossBorder: false,
        ),
        throwsA(
          isA<BookingBlockedException>().having(
            (e) => e.reason,
            'reason',
            BookingBlockedReason.nextOfKinRequired,
          ),
        ),
      );
    });

    test('cross-border missing docs blocks booking', () async {
      final now = DateTime.utc(2026, 3, 2, 8);
      final db = await HailODatabase().open(databasePath: inMemoryDatabasePath);
      addTearDown(db.close);
      final service = RideBookingGuardService(db);

      await db.insert('users', <String, Object?>{
        'id': 'rider_guard_2',
        'role': 'rider',
        'created_at': now.toIso8601String(),
        'updated_at': now.toIso8601String(),
      });
      await db.insert('next_of_kin', <String, Object?>{
        'user_id': 'rider_guard_2',
        'full_name': 'Kin Two',
        'phone': '+234000000002',
        'relationship': 'parent',
        'created_at': now.toIso8601String(),
        'updated_at': now.toIso8601String(),
      });

      expect(
        () => service.assertCanBookRide(
          riderUserId: 'rider_guard_2',
          isCrossBorder: true,
        ),
        throwsA(
          isA<BookingBlockedException>().having(
            (e) => e.reason,
            'reason',
            BookingBlockedReason.crossBorderDocRequired,
          ),
        ),
      );
    });

    test('required docs + next of kin pass', () async {
      final now = DateTime.utc(2026, 3, 2, 8);
      final db = await HailODatabase().open(databasePath: inMemoryDatabasePath);
      addTearDown(db.close);
      final service = RideBookingGuardService(db);

      await db.insert('users', <String, Object?>{
        'id': 'rider_guard_3',
        'role': 'rider',
        'created_at': now.toIso8601String(),
        'updated_at': now.toIso8601String(),
      });
      await db.insert('next_of_kin', <String, Object?>{
        'user_id': 'rider_guard_3',
        'full_name': 'Kin Three',
        'phone': '+234000000003',
        'relationship': 'sibling',
        'created_at': now.toIso8601String(),
        'updated_at': now.toIso8601String(),
      });
      await db.insert('documents', <String, Object?>{
        'id': 'doc_guard_3',
        'user_id': 'rider_guard_3',
        'doc_type': 'ecowas_id',
        'file_ref': '/tmp/ecowas_guard_3.jpg',
        'verified': 1,
        'created_at': now.toIso8601String(),
        'updated_at': now.toIso8601String(),
      });

      await service.assertCanBookRide(
        riderUserId: 'rider_guard_3',
        isCrossBorder: true,
      );
    });
  });
}
