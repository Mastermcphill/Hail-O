import 'package:flutter_test/flutter_test.dart';
import 'package:hail_o_finance_core/data/sqlite/hailo_database.dart';
import 'package:hail_o_finance_core/domain/services/reconciliation_service.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  test('nightly reconciliation flags anomalies', () async {
    final db = await HailODatabase().open(databasePath: inMemoryDatabasePath);
    addTearDown(db.close);
    final now = DateTime.utc(2026, 2, 20, 0, 1);

    await db.insert('wallets', <String, Object?>{
      'owner_id': 'owner_recon',
      'wallet_type': 'driver_a',
      'balance_minor': 9000,
      'reserved_minor': 0,
      'currency': 'NGN',
      'updated_at': now.toIso8601String(),
      'created_at': now.toIso8601String(),
    });

    final service = ReconciliationService(db, nowUtc: () => now);
    final result = await service.runNightlyReconciliation();
    expect(result['anomaly_count'], 1);

    final anomalies = await service.listAnomalies(result['run_id'] as String);
    expect(anomalies.length, 1);
    expect(anomalies.first['entity_type'], 'wallet');
  });
}
