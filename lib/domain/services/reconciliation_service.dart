import 'dart:convert';
import 'dart:math';

import 'package:hail_o_finance_core/sqlite_api.dart';

class ReconciliationService {
  ReconciliationService(this.db, {DateTime Function()? nowUtc})
    : _nowUtc = nowUtc ?? (() => DateTime.now().toUtc());

  final Database db;
  final DateTime Function() _nowUtc;

  Future<Map<String, Object?>> runNightlyReconciliation({
    String? runId,
    String notes = 'nightly_reconciliation',
  }) async {
    final now = _nowUtc();
    final effectiveRunId = runId ?? 'recon_${now.microsecondsSinceEpoch}';
    final startedAtIso = _iso(now);

    return db.transaction((txn) async {
      await txn.insert('reconciliation_runs', <String, Object?>{
        'id': effectiveRunId,
        'started_at': startedAtIso,
        'status': 'running',
        'notes': notes,
      }, conflictAlgorithm: ConflictAlgorithm.replace);

      final anomalies = <Map<String, Object?>>[];
      anomalies.addAll(await _reconcileWallets(txn, effectiveRunId));
      anomalies.addAll(await _reconcileMoneyBox(txn, effectiveRunId));

      for (final anomaly in anomalies) {
        await txn.insert(
          'reconciliation_anomalies',
          anomaly,
          conflictAlgorithm: ConflictAlgorithm.replace,
        );
      }

      final finishedAtIso = _iso(_nowUtc());
      await txn.update(
        'reconciliation_runs',
        <String, Object?>{
          'status': anomalies.isEmpty ? 'clean' : 'anomalies_found',
          'finished_at': finishedAtIso,
          'notes': notes,
        },
        where: 'id = ?',
        whereArgs: <Object>[effectiveRunId],
      );

      return <String, Object?>{
        'ok': true,
        'run_id': effectiveRunId,
        'anomaly_count': anomalies.length,
        'status': anomalies.isEmpty ? 'clean' : 'anomalies_found',
      };
    });
  }

  Future<List<Map<String, Object?>>> listAnomalies(String runId) {
    return db.query(
      'reconciliation_anomalies',
      where: 'run_id = ?',
      whereArgs: <Object>[runId],
      orderBy: 'created_at DESC',
    );
  }

  Future<List<Map<String, Object?>>> _reconcileWallets(
    Transaction txn,
    String runId,
  ) async {
    final anomalies = <Map<String, Object?>>[];
    final walletRows = await txn.query('wallets');

    for (final wallet in walletRows) {
      final ownerId = wallet['owner_id'] as String;
      final walletType = wallet['wallet_type'] as String;
      final actual = (wallet['balance_minor'] as int?) ?? 0;
      final ledgerRows = await txn.query(
        'wallet_ledger',
        columns: <String>['balance_after_minor'],
        where: 'owner_id = ? AND wallet_type = ?',
        whereArgs: <Object>[ownerId, walletType],
        orderBy: 'id DESC',
        limit: 1,
      );
      final expected = ledgerRows.isEmpty
          ? 0
          : (ledgerRows.first['balance_after_minor'] as int?) ?? 0;
      if (expected != actual) {
        anomalies.add(
          _anomaly(
            runId: runId,
            entityType: 'wallet',
            entityId: '$ownerId:$walletType',
            expectedMinor: expected,
            actualMinor: actual,
            severity: 'high',
            details: 'wallet_ledger_balance_mismatch',
          ),
        );
      }
    }

    return anomalies;
  }

  Future<List<Map<String, Object?>>> _reconcileMoneyBox(
    Transaction txn,
    String runId,
  ) async {
    final anomalies = <Map<String, Object?>>[];
    final accountRows = await txn.query('moneybox_accounts');

    for (final account in accountRows) {
      final ownerId = account['owner_id'] as String;
      final actualPrincipal = (account['principal_minor'] as int?) ?? 0;

      final ledgerRows = await txn.query(
        'moneybox_ledger',
        columns: <String>['principal_after_minor'],
        where: 'owner_id = ?',
        whereArgs: <Object>[ownerId],
        orderBy: 'id DESC',
        limit: 1,
      );
      final expectedPrincipal = ledgerRows.isEmpty
          ? 0
          : (ledgerRows.first['principal_after_minor'] as int?) ?? 0;

      if (expectedPrincipal != actualPrincipal) {
        anomalies.add(
          _anomaly(
            runId: runId,
            entityType: 'moneybox_account',
            entityId: ownerId,
            expectedMinor: expectedPrincipal,
            actualMinor: actualPrincipal,
            severity: 'high',
            details: 'moneybox_ledger_principal_mismatch',
          ),
        );
      }
    }

    return anomalies;
  }

  Map<String, Object?> _anomaly({
    required String runId,
    required String entityType,
    required String entityId,
    required int expectedMinor,
    required int actualMinor,
    required String severity,
    required String details,
  }) {
    final now = _nowUtc();
    final suffix = Random().nextInt(1 << 20).toString();
    return <String, Object?>{
      'id': '${runId}_${entityType}_${entityId}_$suffix',
      'run_id': runId,
      'entity_type': entityType,
      'entity_id': entityId,
      'expected_minor': expectedMinor,
      'actual_minor': actualMinor,
      'severity': severity,
      'details': jsonEncode(<String, Object?>{'reason': details}),
      'created_at': _iso(now),
      'resolved_at': null,
    };
  }

  String _iso(DateTime value) => value.toUtc().toIso8601String();
}
