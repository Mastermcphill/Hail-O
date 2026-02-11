import 'package:flutter_test/flutter_test.dart';
import 'package:hail_o_finance_core/data/sqlite/hailo_database.dart';
import 'package:hail_o_finance_core/domain/models/latlng.dart';
import 'package:hail_o_finance_core/domain/services/safety_engine_service.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

class _FakeNotifier implements SafetyNotifier {
  final List<String> inAppMessages = <String>[];
  final List<String> smsMessages = <String>[];
  final List<String> whatsappMessages = <String>[];

  @override
  Future<void> notifyInApp(String message) async {
    inAppMessages.add(message);
  }

  @override
  Future<void> notifySms(String phone, String message) async {
    smsMessages.add('$phone|$message');
  }

  @override
  Future<void> notifyWhatsApp(String phone, String message) async {
    whatsappMessages.add('$phone|$message');
  }
}

void main() {
  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  test('deviation >1km for >5 minutes triggers SOS', () async {
    final db = await HailODatabase().open(databasePath: inMemoryDatabasePath);
    addTearDown(db.close);
    final now = DateTime.utc(2026, 2, 3, 10, 0);
    final notifier = _FakeNotifier();
    final service = SafetyEngineService(
      db,
      notifier: notifier,
      nowUtc: () => now,
    );

    await db.insert('users', <String, Object?>{
      'id': 'rider_safety',
      'role': 'rider',
      'created_at': now.toIso8601String(),
      'updated_at': now.toIso8601String(),
    });
    await db.insert('rides', <String, Object?>{
      'id': 'ride_safety_1',
      'rider_id': 'rider_safety',
      'trip_scope': 'intra_city',
      'status': 'in_progress',
      'bidding_mode': 1,
      'base_fare_minor': 9000,
      'premium_markup_minor': 0,
      'charter_mode': 0,
      'daily_rate_minor': 0,
      'total_fare_minor': 9000,
      'connection_fee_minor': 0,
      'connection_fee_paid': 0,
      'created_at': now.toIso8601String(),
      'updated_at': now.toIso8601String(),
    });

    final route = <LatLng>[
      const LatLng(latitude: 6.5244, longitude: 3.3792),
      const LatLng(latitude: 6.5244, longitude: 3.4892),
    ];
    final farPoint = const LatLng(latitude: 6.6000, longitude: 3.6000);

    final sample1 = await service.ingestLocationSample(
      rideId: 'ride_safety_1',
      currentPosition: farPoint,
      routePolyline: route,
      nextOfKinPhone: '+2348000000000',
      idempotencyKey: 'safety_sample_1',
      sampledAtUtc: now,
    );
    expect(sample1['sos_triggered'], false);

    final sample2 = await service.ingestLocationSample(
      rideId: 'ride_safety_1',
      currentPosition: farPoint,
      routePolyline: route,
      nextOfKinPhone: '+2348000000000',
      idempotencyKey: 'safety_sample_2',
      sampledAtUtc: now.add(const Duration(minutes: 6)),
    );
    expect(sample2['sos_triggered'], true);

    final rows = await db.query(
      'safety_events',
      where: 'ride_id = ? AND event_type = ?',
      whereArgs: const <Object>['ride_safety_1', 'sos_deviation'],
    );
    expect(rows.length, 1);
    expect(notifier.smsMessages.isNotEmpty, true);
    expect(notifier.whatsappMessages.isNotEmpty, true);
  });
}
