import 'package:hail_o_finance_core/sqlite_api.dart';

import '../../../domain/models/next_of_kin.dart';
import '../table_names.dart';

class NextOfKinDao {
  const NextOfKinDao(this.db);

  final DatabaseExecutor db;

  Future<void> upsert(NextOfKin nextOfKin) async {
    await db.insert(
      TableNames.nextOfKin,
      nextOfKin.toMap(),
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  Future<bool> existsForUser(String userId) async {
    final rows = await db.query(
      TableNames.nextOfKin,
      columns: <String>['user_id'],
      where: 'user_id = ?',
      whereArgs: <Object>[userId],
      limit: 1,
    );
    return rows.isNotEmpty;
  }

  Future<NextOfKin?> findByUser(String userId) async {
    final rows = await db.query(
      TableNames.nextOfKin,
      where: 'user_id = ?',
      whereArgs: <Object>[userId],
      limit: 1,
    );
    if (rows.isEmpty) {
      return null;
    }
    return NextOfKin.fromMap(rows.first);
  }
}
