import 'package:sqflite/sqflite.dart';

import '../../../domain/models/penalty_rule.dart';
import '../table_names.dart';

class PenaltyRulesDao {
  const PenaltyRulesDao(this.db);

  final DatabaseExecutor db;

  Future<PenaltyRule?> findActiveRule({
    required DateTime asOfUtc,
    required String scope,
  }) async {
    final asOf = asOfUtc.toUtc().toIso8601String();
    var rows = await db.query(
      TableNames.penaltyRules,
      where: 'scope = ? AND effective_from <= ?',
      whereArgs: <Object>[scope, asOf],
      orderBy: 'effective_from DESC, version DESC',
      limit: 1,
    );
    if (rows.isEmpty) {
      rows = await db.query(
        TableNames.penaltyRules,
        where: 'scope = ? AND effective_from <= ?',
        whereArgs: <Object>['default', asOf],
        orderBy: 'effective_from DESC, version DESC',
        limit: 1,
      );
    }
    if (rows.isEmpty) {
      return null;
    }
    return PenaltyRule.fromMap(rows.first);
  }

  Future<void> upsert(PenaltyRule rule) async {
    await db.insert(
      TableNames.penaltyRules,
      rule.toMap(),
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }
}
