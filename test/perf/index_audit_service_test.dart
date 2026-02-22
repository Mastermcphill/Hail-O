import 'package:flutter_test/flutter_test.dart';
import 'package:hail_o_finance_core/data/sqlite/hailo_database.dart';
import 'package:hail_o_finance_core/domain/services/index_audit_service.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  test(
    'index audit service validates required index set on head schema',
    () async {
      final db = await HailODatabase().open(databasePath: inMemoryDatabasePath);
      addTearDown(db.close);

      final report = await IndexAuditService(db).auditRequiredIndexes();
      expect(report.ok, true, reason: report.toMap().toString());
      expect(report.issues, isEmpty);
    },
  );
}
