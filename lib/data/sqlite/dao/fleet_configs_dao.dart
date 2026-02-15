import 'package:hail_o_finance_core/sqlite_api.dart';

class FleetConfigsDao {
  const FleetConfigsDao(this.db);

  final DatabaseExecutor db;

  Future<void> upsert({
    required String fleetOwnerId,
    required int allowancePercent,
    required String nowIso,
  }) async {
    await db.insert('fleet_configs', <String, Object?>{
      'fleet_owner_id': fleetOwnerId,
      'allowance_percent': allowancePercent,
      'created_at': nowIso,
      'updated_at': nowIso,
    }, conflictAlgorithm: ConflictAlgorithm.replace);
  }

  Future<int> getAllowancePercent(String fleetOwnerId) async {
    final rows = await db.query(
      'fleet_configs',
      columns: <String>['allowance_percent'],
      where: 'fleet_owner_id = ?',
      whereArgs: <Object>[fleetOwnerId],
      limit: 1,
    );
    if (rows.isEmpty) {
      return 0;
    }
    return ((rows.first['allowance_percent'] as int?) ?? 0).clamp(0, 100);
  }
}
