import 'package:sqflite/sqflite.dart';

Future<List<String>> explainQueryPlan(
  DatabaseExecutor db, {
  required String sql,
  List<Object?> args = const <Object?>[],
}) async {
  final rows = await db.rawQuery('EXPLAIN QUERY PLAN $sql', args);
  return rows
      .map(
        (row) =>
            ((row['detail'] ?? row['DETAIL']) as String?)?.trim() ??
            row.toString(),
      )
      .toList(growable: false);
}

bool queryPlanUsesIndex(List<String> details, {String? indexName}) {
  for (final detail in details) {
    final normalized = detail.toUpperCase();
    final hasIndexHint =
        normalized.contains('USING INDEX') ||
        normalized.contains('USING COVERING INDEX');
    if (!hasIndexHint) {
      continue;
    }
    if (indexName == null) {
      return true;
    }
    if (normalized.contains(indexName.toUpperCase())) {
      return true;
    }
  }
  return false;
}
