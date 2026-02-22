import 'dart:convert';

import 'package:sqflite/sqflite.dart';

import 'sim_types.dart';

Future<String> buildScenarioReportJson({
  required Database db,
  required SimScenarioConfig config,
  required int failedStepIndex,
  required SimStepType failedStepType,
  required Object error,
  required StackTrace stackTrace,
  required List<SimStepResult> stepResults,
  int ledgerTail = 20,
  int rideEventTail = 20,
}) async {
  final rideRows = await db.query(
    'rides',
    where: 'id = ?',
    whereArgs: <Object>[config.entityIds.rideId],
    limit: 1,
  );
  final escrowRows = await db.query(
    'escrow_holds',
    where: 'id = ?',
    whereArgs: <Object>[config.entityIds.escrowId],
    limit: 1,
  );
  final payoutRows = await db.query(
    'payout_records',
    where: 'escrow_id = ?',
    whereArgs: <Object>[config.entityIds.escrowId],
    orderBy: 'created_at DESC',
    limit: 1,
  );
  final penaltyRows = await db.query(
    'penalty_records',
    where: 'ride_id = ?',
    whereArgs: <Object>[config.entityIds.rideId],
    orderBy: 'created_at DESC',
    limit: 20,
  );
  final walletLedgerRows = await db.query(
    'wallet_ledger',
    where: 'reference_id = ?',
    whereArgs: <Object>[config.entityIds.rideId],
    orderBy: 'id DESC',
    limit: ledgerTail,
  );
  final rideEventRows = await db.query(
    'ride_events',
    where: 'ride_id = ?',
    whereArgs: <Object>[config.entityIds.rideId],
    orderBy: 'created_at DESC',
    limit: rideEventTail,
  );

  final report = <String, Object?>{
    'seed': config.seed,
    'scenario_id': config.scenarioId,
    'failed_step_index': failedStepIndex,
    'failed_step_type': failedStepType.code,
    'error_type': error.runtimeType.toString(),
    'error': error.toString(),
    'stack_trace': stackTrace.toString(),
    'entity_ids': <String, Object?>{
      'ride_id': config.entityIds.rideId,
      'rider_id': config.entityIds.riderId,
      'driver_id': config.entityIds.driverId,
      'alt_driver_id': config.entityIds.altDriverId,
      'escrow_id': config.entityIds.escrowId,
      'dispute_id': config.entityIds.disputeId,
    },
    'step_results': stepResults.map((row) => row.toMap()).toList(),
    'db_snapshot': <String, Object?>{
      'ride': _firstRowOrNull(rideRows),
      'escrow': _firstRowOrNull(escrowRows),
      'payout': _firstRowOrNull(payoutRows),
      'penalty_records': penaltyRows.map(_copyRow).toList(),
      'wallet_ledger_tail': walletLedgerRows.map(_copyRow).toList(),
      'ride_events_tail': rideEventRows.map(_copyRow).toList(),
    },
  };

  return const JsonEncoder.withIndent('  ').convert(report);
}

Map<String, Object?>? _firstRowOrNull(List<Map<String, Object?>> rows) {
  if (rows.isEmpty) {
    return null;
  }
  return _copyRow(rows.first);
}

Map<String, Object?> _copyRow(Map<String, Object?> row) {
  return Map<String, Object?>.from(row);
}
