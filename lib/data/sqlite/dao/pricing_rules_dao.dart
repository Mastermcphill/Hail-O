import 'package:hail_o_finance_core/sqlite_api.dart';

import '../../../domain/models/pricing_rule.dart';
import '../table_names.dart';

class PricingRulesDao {
  const PricingRulesDao(this.db);

  final DatabaseExecutor db;

  Future<PricingRule?> findActiveRule({
    required DateTime asOfUtc,
    required String scope,
  }) async {
    final rules = await listActiveRules(asOfUtc: asOfUtc, scope: scope);
    if (rules.isEmpty) {
      return null;
    }
    return rules.first;
  }

  Future<List<PricingRule>> listActiveRules({
    required DateTime asOfUtc,
    required String scope,
  }) async {
    final asOf = asOfUtc.toUtc().toIso8601String();
    var rows = await db.query(
      TableNames.pricingRules,
      where: 'scope = ? AND enabled = 1 AND effective_from <= ?',
      whereArgs: <Object>[scope, asOf],
      orderBy: 'effective_from DESC, version DESC',
    );
    if (rows.isEmpty && scope != 'default') {
      rows = await db.query(
        TableNames.pricingRules,
        where: 'scope = ? AND enabled = 1 AND effective_from <= ?',
        whereArgs: <Object>['default', asOf],
        orderBy: 'effective_from DESC, version DESC',
      );
    }
    return rows.map(PricingRule.fromMap).toList(growable: false);
  }

  Future<void> upsert(PricingRule rule) async {
    await db.insert(
      TableNames.pricingRules,
      rule.toMap(),
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }
}
