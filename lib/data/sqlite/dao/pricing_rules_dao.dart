import 'package:sqflite/sqflite.dart';

import '../../../domain/models/pricing_rule.dart';
import '../table_names.dart';

class PricingRulesDao {
  const PricingRulesDao(this.db);

  final DatabaseExecutor db;

  Future<PricingRule?> findActiveRule({
    required DateTime asOfUtc,
    required String scope,
  }) async {
    final asOf = asOfUtc.toUtc().toIso8601String();
    var rows = await db.query(
      TableNames.pricingRules,
      where: 'scope = ? AND effective_from <= ?',
      whereArgs: <Object>[scope, asOf],
      orderBy: 'effective_from DESC, version DESC',
      limit: 1,
    );
    if (rows.isEmpty) {
      rows = await db.query(
        TableNames.pricingRules,
        where: 'scope = ? AND effective_from <= ?',
        whereArgs: <Object>['default', asOf],
        orderBy: 'effective_from DESC, version DESC',
        limit: 1,
      );
    }
    if (rows.isEmpty) {
      return null;
    }
    return PricingRule.fromMap(rows.first);
  }

  Future<void> upsert(PricingRule rule) async {
    await db.insert(
      TableNames.pricingRules,
      rule.toMap(),
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }
}
