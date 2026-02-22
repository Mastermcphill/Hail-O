import 'package:hail_o_finance_core/sqlite_api.dart';

class IndexAuditRequirement {
  const IndexAuditRequirement({
    required this.table,
    required this.columns,
    this.requireUnique = false,
    this.label = '',
  });

  final String table;
  final List<String> columns;
  final bool requireUnique;
  final String label;
}

class IndexAuditIssue {
  const IndexAuditIssue({
    required this.table,
    required this.columns,
    required this.requireUnique,
    required this.label,
  });

  final String table;
  final List<String> columns;
  final bool requireUnique;
  final String label;

  Map<String, Object?> toMap() {
    return <String, Object?>{
      'table': table,
      'columns': columns,
      'require_unique': requireUnique,
      'label': label,
    };
  }
}

class IndexAuditReport {
  const IndexAuditReport({required this.ok, required this.issues});

  final bool ok;
  final List<IndexAuditIssue> issues;

  Map<String, Object?> toMap() {
    return <String, Object?>{
      'ok': ok,
      'issues': issues.map((issue) => issue.toMap()).toList(),
      'issue_count': issues.length,
    };
  }
}

class IndexAuditService {
  const IndexAuditService(this.db);

  final DatabaseExecutor db;

  static const List<IndexAuditRequirement> requiredIndexes =
      <IndexAuditRequirement>[
        IndexAuditRequirement(
          table: 'wallet_ledger',
          columns: <String>['idempotency_scope', 'idempotency_key'],
          label: 'wallet ledger idempotency guard',
        ),
        IndexAuditRequirement(
          table: 'wallet_ledger',
          columns: <String>['owner_id', 'wallet_type', 'created_at'],
          label: 'wallet statement hot path',
        ),
        IndexAuditRequirement(
          table: 'payout_records',
          columns: <String>['escrow_id'],
          requireUnique: true,
          label: 'one payout per escrow',
        ),
        IndexAuditRequirement(
          table: 'penalty_records',
          columns: <String>['ride_id', 'created_at'],
          label: 'penalty history by ride',
        ),
        IndexAuditRequirement(
          table: 'ride_events',
          columns: <String>['ride_id', 'created_at'],
          label: 'ride event stream by ride',
        ),
        IndexAuditRequirement(
          table: 'pricing_rules',
          columns: <String>['scope', 'effective_from'],
          label: 'active pricing rule lookup',
        ),
        IndexAuditRequirement(
          table: 'penalty_rules',
          columns: <String>['scope', 'effective_from'],
          label: 'active penalty rule lookup',
        ),
        IndexAuditRequirement(
          table: 'compliance_requirements',
          columns: <String>['scope', 'from_country', 'to_country'],
          label: 'compliance requirement lookup',
        ),
      ];

  Future<IndexAuditReport> auditRequiredIndexes({
    List<IndexAuditRequirement> requirements = requiredIndexes,
  }) async {
    final issues = <IndexAuditIssue>[];
    for (final requirement in requirements) {
      final hasIndex = await _hasMatchingIndex(
        table: requirement.table,
        columns: requirement.columns,
        requireUnique: requirement.requireUnique,
      );
      if (!hasIndex) {
        issues.add(
          IndexAuditIssue(
            table: requirement.table,
            columns: requirement.columns,
            requireUnique: requirement.requireUnique,
            label: requirement.label,
          ),
        );
      }
    }
    return IndexAuditReport(ok: issues.isEmpty, issues: issues);
  }

  Future<bool> _hasMatchingIndex({
    required String table,
    required List<String> columns,
    required bool requireUnique,
  }) async {
    final indexList = await db.rawQuery("PRAGMA index_list('$table')");
    for (final row in indexList) {
      final indexName = row['name'] as String?;
      if (indexName == null || indexName.isEmpty) {
        continue;
      }
      final unique = (row['unique'] as num?)?.toInt() == 1;
      if (requireUnique && !unique) {
        continue;
      }
      final indexInfo = await db.rawQuery("PRAGMA index_info('$indexName')");
      final ordered = indexInfo.toList()
        ..sort(
          (a, b) => ((a['seqno'] as num?)?.toInt() ?? 0).compareTo(
            (b['seqno'] as num?)?.toInt() ?? 0,
          ),
        );
      final indexColumns = ordered
          .map((item) => (item['name'] as String?) ?? '')
          .where((name) => name.isNotEmpty)
          .toList(growable: false);
      if (_startsWith(indexColumns, columns)) {
        return true;
      }
    }
    return false;
  }

  bool _startsWith(List<String> haystack, List<String> needle) {
    if (haystack.length < needle.length) {
      return false;
    }
    for (var i = 0; i < needle.length; i++) {
      if (haystack[i] != needle[i]) {
        return false;
      }
    }
    return true;
  }
}
