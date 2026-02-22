import 'package:hail_o_finance_core/sqlite_api.dart';

import '../../../domain/models/compliance_requirement.dart';
import '../table_names.dart';

class ComplianceRequirementsDao {
  const ComplianceRequirementsDao(this.db);

  final DatabaseExecutor db;

  Future<ComplianceRequirement?> findApplicableRequirement({
    required String scope,
    String? fromCountry,
    String? toCountry,
  }) async {
    final normalizedScope = scope.trim().toLowerCase();
    final from = fromCountry?.trim().toUpperCase();
    final to = toCountry?.trim().toUpperCase();

    final exact = await _findByScopeAndRoute(
      scope: normalizedScope,
      fromCountry: from,
      toCountry: to,
    );
    if (exact != null) {
      return exact;
    }

    final scopeDefault = await _findByScopeAndRoute(
      scope: normalizedScope,
      fromCountry: null,
      toCountry: null,
    );
    if (scopeDefault != null) {
      return scopeDefault;
    }

    return _findByScopeAndRoute(
      scope: 'default',
      fromCountry: null,
      toCountry: null,
    );
  }

  Future<ComplianceRequirement?> _findByScopeAndRoute({
    required String scope,
    required String? fromCountry,
    required String? toCountry,
  }) async {
    final whereClauses = <String>['scope = ?'];
    whereClauses.add('enabled = 1');
    final whereArgs = <Object?>[scope];
    if (fromCountry == null) {
      whereClauses.add('from_country IS NULL');
    } else {
      whereClauses.add('from_country = ?');
      whereArgs.add(fromCountry);
    }
    if (toCountry == null) {
      whereClauses.add('to_country IS NULL');
    } else {
      whereClauses.add('to_country = ?');
      whereArgs.add(toCountry);
    }
    final rows = await db.query(
      TableNames.complianceRequirements,
      where: whereClauses.join(' AND '),
      whereArgs: whereArgs,
      limit: 1,
    );
    if (rows.isEmpty) {
      return null;
    }
    return ComplianceRequirement.fromMap(rows.first);
  }

  Future<void> upsert(ComplianceRequirement requirement) async {
    await db.insert(
      TableNames.complianceRequirements,
      requirement.toMap(),
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }
}
