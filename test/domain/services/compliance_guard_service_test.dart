import 'package:flutter_test/flutter_test.dart';
import 'package:hail_o_finance_core/data/sqlite/hailo_database.dart';
import 'package:hail_o_finance_core/domain/models/ride_trip.dart';
import 'package:hail_o_finance_core/domain/services/compliance_guard_service.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  group('ComplianceGuardService', () {
    test('cross-border booking blocks when document is expired', () async {
      final now = DateTime.utc(2026, 2, 11, 12);
      final db = await HailODatabase().open(databasePath: inMemoryDatabasePath);
      addTearDown(db.close);

      await _seedRiderWithKin(db, riderId: 'rider_compliance_1', now: now);
      await db.insert('documents', <String, Object?>{
        'id': 'doc_expired',
        'user_id': 'rider_compliance_1',
        'doc_type': 'passport',
        'file_ref': 'passport://expired',
        'verified': 1,
        'status': 'verified',
        'country': 'GH',
        'expires_at': now.subtract(const Duration(days: 1)).toIso8601String(),
        'verified_at': now.subtract(const Duration(days: 30)).toIso8601String(),
        'created_at': now.subtract(const Duration(days: 30)).toIso8601String(),
        'updated_at': now.subtract(const Duration(days: 1)).toIso8601String(),
      });

      final service = ComplianceGuardService(db, nowUtc: () => now);

      expect(
        () => service.assertEligibleForTrip(
          riderUserId: 'rider_compliance_1',
          tripScope: TripScope.international,
          destinationCountry: 'GH',
        ),
        throwsA(
          isA<ComplianceBlockedException>().having(
            (e) => e.reason,
            'reason',
            ComplianceBlockedReason.crossBorderDocExpired,
          ),
        ),
      );
    });

    test(
      'cross-border booking passes with verified non-expired matching doc',
      () async {
        final now = DateTime.utc(2026, 2, 11, 12);
        final db = await HailODatabase().open(
          databasePath: inMemoryDatabasePath,
        );
        addTearDown(db.close);

        await _seedRiderWithKin(db, riderId: 'rider_compliance_2', now: now);
        await db.insert('documents', <String, Object?>{
          'id': 'doc_valid',
          'user_id': 'rider_compliance_2',
          'doc_type': 'ecowas_id',
          'file_ref': 'ecowas://valid',
          'verified': 1,
          'status': 'verified',
          'country': 'NG',
          'expires_at': now.add(const Duration(days: 365)).toIso8601String(),
          'verified_at': now
              .subtract(const Duration(days: 10))
              .toIso8601String(),
          'created_at': now
              .subtract(const Duration(days: 10))
              .toIso8601String(),
          'updated_at': now.toIso8601String(),
        });

        final service = ComplianceGuardService(db, nowUtc: () => now);

        await service.assertEligibleForTrip(
          riderUserId: 'rider_compliance_2',
          tripScope: TripScope.crossCountry,
          originCountry: 'NG',
        );
      },
    );
  });
}

Future<void> _seedRiderWithKin(
  dynamic db, {
  required String riderId,
  required DateTime now,
}) async {
  await db.insert('users', <String, Object?>{
    'id': riderId,
    'role': 'rider',
    'created_at': now.toIso8601String(),
    'updated_at': now.toIso8601String(),
  });
  await db.insert('next_of_kin', <String, Object?>{
    'user_id': riderId,
    'full_name': 'Compliance Kin',
    'phone': '+234000000500',
    'relationship': 'parent',
    'created_at': now.toIso8601String(),
    'updated_at': now.toIso8601String(),
  });
}
