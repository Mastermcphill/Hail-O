import 'dart:io';

import 'package:hail_o_finance_core/domain/errors/domain_errors.dart';
import 'package:hail_o_finance_core/domain/services/ledger_invariant_service.dart';
import 'package:sqflite/sqflite.dart';

import 'scenario_actions.dart';
import 'scenario_report.dart';
import 'sim_types.dart';

class ScenarioRunner {
  ScenarioRunner(
    this.db, {
    required DateTime startUtc,
    this.writeArtifactsOnFailure = false,
  }) : _clock = SimClock(startUtc.toUtc());

  final Database db;
  final bool writeArtifactsOnFailure;
  final SimClock _clock;
  late final ScenarioActions _actions = ScenarioActions(
    db,
    nowUtc: _clock.call,
  );

  Future<SimScenarioResult> runRandomScenario(SimScenarioConfig config) async {
    final rng = SeededRng(config.seed ^ config.scenarioId.hashCode);
    final planned = _buildStepPlan(config.stepCount, rng);
    return runScenario(config: config, steps: planned, rng: rng);
  }

  Future<SimScenarioResult> runScenario({
    required SimScenarioConfig config,
    required List<SimStepType> steps,
    SeededRng? rng,
  }) async {
    final localRng = rng ?? SeededRng(config.seed);
    final state = SimMutableState();
    final results = <SimStepResult>[];
    final invariants = LedgerInvariantService(db);

    for (var i = 0; i < steps.length; i++) {
      final step = steps[i];
      try {
        final response = await _actions.runStep(
          config: config,
          stepType: step,
          stepIndex: i,
          rng: localRng,
        );
        final ok = response['ok'] == true;
        results.add(
          SimStepResult(
            stepIndex: i,
            stepType: step,
            ok: ok,
            response: Map<String, Object?>.from(response),
            errorType: ok ? null : 'StepReturnedNotOk',
            errorCode: ok ? null : (response['error'] as String?),
          ),
        );
        if (!ok) {
          throw DomainInvariantError(
            code: 'sim_step_not_ok',
            metadata: <String, Object?>{
              'step': step.code,
              'response': response,
            },
          );
        }

        await _actions.syncState(config: config, state: state);
        await _assertPostStepInvariants(config: config, state: state);

        final ledgerCheck = await invariants.verifySnapshot();
        if (ledgerCheck['ok'] != true) {
          throw DomainInvariantError(
            code: 'sim_ledger_invariant_failed',
            metadata: <String, Object?>{'snapshot': ledgerCheck},
          );
        }
        _clock.advance(const Duration(minutes: 1));
      } catch (error, stackTrace) {
        final reportJson = await buildScenarioReportJson(
          db: db,
          config: config,
          failedStepIndex: i,
          failedStepType: step,
          error: error,
          stackTrace: stackTrace,
          stepResults: results,
        );
        if (writeArtifactsOnFailure) {
          await _writeFailureArtifact(config, reportJson);
        }
        return SimScenarioResult(
          ok: false,
          seed: config.seed,
          scenarioId: config.scenarioId,
          stepResults: results,
          errorType: error.runtimeType.toString(),
          errorCode: error is DomainError ? error.code : null,
          reportJson: reportJson,
        );
      }
    }

    return SimScenarioResult(
      ok: true,
      seed: config.seed,
      scenarioId: config.scenarioId,
      stepResults: results,
    );
  }

  List<SimStepType> _buildStepPlan(int stepCount, SeededRng rng) {
    final plan = <SimStepType>[];
    for (var i = 0; i < stepCount; i++) {
      if (i == 0) {
        plan.add(SimStepType.bookRide);
      } else if (i == 1) {
        plan.add(SimStepType.acceptRide);
      } else if (i == 2) {
        plan.add(SimStepType.startRide);
      } else if (i == 3) {
        plan.add(SimStepType.completeRide);
      } else if (i == 4) {
        plan.add(SimStepType.settleRide);
      } else if (i == 5) {
        plan.add(SimStepType.openDispute);
      } else if (i == 6) {
        plan.add(SimStepType.resolveDispute);
      } else if (i == 7) {
        plan.add(SimStepType.reverseLatestCredit);
      } else {
        final bucket = rng.nextInt(4);
        switch (bucket) {
          case 0:
            plan.add(SimStepType.settleRide);
            break;
          case 1:
            plan.add(SimStepType.resolveDispute);
            break;
          case 2:
            plan.add(SimStepType.reverseLatestCredit);
            break;
          case 3:
            plan.add(SimStepType.openDispute);
            break;
          default:
            plan.add(SimStepType.resolveDispute);
            break;
        }
      }
    }
    return plan;
  }

  Future<void> _assertPostStepInvariants({
    required SimScenarioConfig config,
    required SimMutableState state,
  }) async {
    final payoutRows = await db.query(
      'payout_records',
      columns: <String>['COUNT(*) AS row_count'],
      where: 'escrow_id = ?',
      whereArgs: <Object>[config.entityIds.escrowId],
      limit: 1,
    );
    final payoutCount = (payoutRows.first['row_count'] as num?)?.toInt() ?? 0;
    if (payoutCount > 1) {
      throw const DomainInvariantError(code: 'sim_duplicate_payout_per_escrow');
    }

    final reversalRows = await db.query('wallet_reversals');
    for (final row in reversalRows) {
      final originalLedgerId = (row['original_ledger_id'] as num?)?.toInt();
      final reversalLedgerId = (row['reversal_ledger_id'] as num?)?.toInt();
      if (originalLedgerId == null || reversalLedgerId == null) {
        throw const DomainInvariantError(code: 'sim_orphan_reversal_record');
      }
      final ledgerRows = await db.query(
        'wallet_ledger',
        columns: <String>['id'],
        where: 'id IN (?, ?)',
        whereArgs: <Object>[originalLedgerId, reversalLedgerId],
      );
      if (ledgerRows.length != 2) {
        throw const DomainInvariantError(
          code: 'sim_reversal_link_target_missing',
        );
      }
    }

    if (state.booked) {
      final eventRows = await db.query(
        'ride_events',
        columns: <String>['event_type'],
        where: 'ride_id = ?',
        whereArgs: <Object>[config.entityIds.rideId],
      );
      final types = eventRows
          .map((row) => (row['event_type'] as String?) ?? '')
          .toSet();
      if (!types.contains('RIDE_BOOKED')) {
        throw const DomainInvariantError(code: 'sim_missing_ride_booked_event');
      }
      if (state.accepted && !types.contains('DRIVER_ACCEPTED')) {
        throw const DomainInvariantError(
          code: 'sim_missing_driver_accepted_event',
        );
      }
      if (state.started && !types.contains('RIDE_STARTED')) {
        throw const DomainInvariantError(
          code: 'sim_missing_ride_started_event',
        );
      }
      if (state.completed && !types.contains('RIDE_COMPLETED')) {
        throw const DomainInvariantError(
          code: 'sim_missing_ride_completed_event',
        );
      }
      if (state.cancelled && !types.contains('RIDE_CANCELLED')) {
        throw const DomainInvariantError(
          code: 'sim_missing_ride_cancelled_event',
        );
      }
    }

    final orphanDisputeEvents = await db.rawQuery('''
      SELECT e.id
      FROM dispute_events e
      LEFT JOIN disputes d ON d.id = e.dispute_id
      WHERE d.id IS NULL
      LIMIT 1
    ''');
    if (orphanDisputeEvents.isNotEmpty) {
      throw const DomainInvariantError(code: 'sim_orphan_dispute_event');
    }

    final orphanPayouts = await db.rawQuery('''
      SELECT p.id
      FROM payout_records p
      LEFT JOIN escrow_holds e ON e.id = p.escrow_id
      WHERE e.id IS NULL
      LIMIT 1
    ''');
    if (orphanPayouts.isNotEmpty) {
      throw const DomainInvariantError(code: 'sim_orphan_payout_record');
    }
  }

  Future<void> _writeFailureArtifact(
    SimScenarioConfig config,
    String reportJson,
  ) async {
    final dir = Directory('test_artifacts');
    if (!dir.existsSync()) {
      dir.createSync(recursive: true);
    }
    final filePath =
        'test_artifacts/sim_${config.seed}_${config.scenarioId}_failure.json';
    await File(filePath).writeAsString(reportJson);
  }
}
