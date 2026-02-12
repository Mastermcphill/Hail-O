import 'package:sqflite/sqflite.dart';

import '../../data/sqlite/table_names.dart';
import '../models/sync_snapshot.dart';
import 'ledger_invariant_service.dart';

class SyncSnapshotService {
  const SyncSnapshotService(this.db);

  final Database db;

  static const List<String> _exportTablesInOrder = <String>[
    TableNames.users,
    TableNames.nextOfKin,
    TableNames.documents,
    TableNames.rides,
    TableNames.escrowHolds,
    TableNames.disputes,
    TableNames.rideEvents,
    TableNames.escrowEvents,
    TableNames.walletEvents,
    TableNames.disputeEvents,
    TableNames.wallets,
    TableNames.walletTransfers,
    TableNames.walletLedger,
    TableNames.walletReversals,
    TableNames.payoutRecords,
    TableNames.penaltyRecords,
    TableNames.pricingRules,
    TableNames.penaltyRules,
    TableNames.complianceRequirements,
  ];

  Future<SyncSnapshot> exportSnapshot({DateTime? sinceTimestamp}) async {
    final schemaVersion = await _schemaVersion();
    final tables = <String, List<Map<String, Object?>>>{};
    for (final table in _exportTablesInOrder) {
      tables[table] = await _exportTableRows(
        table,
        sinceTimestamp: sinceTimestamp,
      );
    }
    return SyncSnapshot(
      schemaVersion: schemaVersion,
      exportedAtUtc: DateTime.now().toUtc(),
      tables: tables,
    );
  }

  Future<Map<String, Object?>> importSnapshot(SyncSnapshot snapshot) async {
    var inserted = 0;
    var ignored = 0;
    await db.transaction((txn) async {
      for (final table in _exportTablesInOrder) {
        final rows = snapshot.tables[table] ?? const <Map<String, Object?>>[];
        for (final row in rows) {
          try {
            final result = await txn.insert(
              table,
              Map<String, Object?>.from(row),
              conflictAlgorithm: ConflictAlgorithm.ignore,
            );
            if (result > 0) {
              inserted++;
            } else {
              ignored++;
            }
          } on DatabaseException {
            ignored++;
          }
        }
      }
    });

    final invariants = await LedgerInvariantService(db).verifySnapshot();
    return <String, Object?>{
      'ok': invariants['ok'] == true,
      'schema_version': snapshot.schemaVersion,
      'inserted_rows': inserted,
      'ignored_rows': ignored,
      'invariants': invariants,
    };
  }

  Future<int> _schemaVersion() async {
    final rows = await db.rawQuery(
      'SELECT MAX(version) AS max_version FROM ${TableNames.schemaMigrations}',
    );
    return (rows.first['max_version'] as num?)?.toInt() ?? 0;
  }

  Future<List<Map<String, Object?>>> _exportTableRows(
    String table, {
    DateTime? sinceTimestamp,
  }) async {
    final columns = await _tableColumns(table);
    final hasCreatedAt = columns.contains('created_at');
    final hasId = columns.contains('id');

    final whereClauses = <String>[];
    final whereArgs = <Object?>[];
    if (sinceTimestamp != null && hasCreatedAt) {
      whereClauses.add('created_at >= ?');
      whereArgs.add(sinceTimestamp.toUtc().toIso8601String());
    }

    final orderByParts = <String>[];
    if (hasCreatedAt) {
      orderByParts.add('created_at ASC');
    }
    if (hasId) {
      orderByParts.add('id ASC');
    }

    final rows = await db.query(
      table,
      where: whereClauses.isEmpty ? null : whereClauses.join(' AND '),
      whereArgs: whereClauses.isEmpty ? null : whereArgs,
      orderBy: orderByParts.isEmpty ? null : orderByParts.join(', '),
    );
    return rows
        .map((row) => Map<String, Object?>.from(row))
        .toList(growable: false);
  }

  Future<Set<String>> _tableColumns(String table) async {
    final rows = await db.rawQuery("PRAGMA table_info('$table')");
    return rows
        .map((row) => (row['name'] as String?) ?? '')
        .where((column) => column.isNotEmpty)
        .toSet();
  }
}
