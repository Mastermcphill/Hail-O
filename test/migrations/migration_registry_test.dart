import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'fixtures/old_state_fixture_builder.dart';

void main() {
  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  test('migration registry is strictly ordered and unique', () {
    final migrations = allMigrations();
    final versions = migrations.map((migration) => migration.version).toList();
    final sorted = List<int>.from(versions)..sort();
    expect(versions, sorted);
    expect(versions.toSet().length, versions.length);
  });

  test('head schema keeps required unique constraints and indexes', () async {
    final db = await openDatabaseAtVersion(
      maxVersion: allMigrations().last.version,
    );
    addTearDown(db.close);

    expect(
      await _hasIndex(
        db,
        table: 'wallet_ledger',
        columns: const <String>['idempotency_scope', 'idempotency_key'],
      ),
      true,
    );
    expect(
      await _hasIndex(
        db,
        table: 'ride_events',
        columns: const <String>['idempotency_scope', 'idempotency_key'],
        requireUnique: true,
      ),
      true,
    );
    expect(
      await _hasIndex(
        db,
        table: 'escrow_events',
        columns: const <String>['idempotency_scope', 'idempotency_key'],
        requireUnique: true,
      ),
      true,
    );
    expect(
      await _hasIndex(
        db,
        table: 'wallet_events',
        columns: const <String>['idempotency_scope', 'idempotency_key'],
        requireUnique: true,
      ),
      true,
    );
    expect(
      await _hasIndex(
        db,
        table: 'payout_records',
        columns: const <String>['escrow_id'],
        requireUnique: true,
      ),
      true,
    );
    expect(
      await _hasIndex(
        db,
        table: 'wallet_reversals',
        columns: const <String>['original_ledger_id'],
        requireUnique: true,
      ),
      true,
    );
    expect(
      await _hasIndex(
        db,
        table: 'pricing_rules',
        columns: const <String>['scope', 'effective_from'],
      ),
      true,
    );
    expect(
      await _hasIndex(
        db,
        table: 'penalty_rules',
        columns: const <String>['scope', 'effective_from'],
      ),
      true,
    );
    expect(
      await _hasIndex(
        db,
        table: 'compliance_requirements',
        columns: const <String>['scope', 'from_country', 'to_country'],
      ),
      true,
    );
  });
}

Future<bool> _hasIndex(
  Database db, {
  required String table,
  required List<String> columns,
  bool requireUnique = false,
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
    final infoRows = await db.rawQuery("PRAGMA index_info('$indexName')");
    final sorted = infoRows.toList()
      ..sort(
        (a, b) => ((a['seqno'] as num?)?.toInt() ?? 0).compareTo(
          (b['seqno'] as num?)?.toInt() ?? 0,
        ),
      );
    final indexedColumns = sorted
        .map((info) => (info['name'] as String?) ?? '')
        .where((name) => name.isNotEmpty)
        .toList(growable: false);
    if (_startsWith(indexedColumns, columns)) {
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
