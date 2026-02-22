import 'package:sqflite/sqflite.dart';

import 'package:hail_o_finance_core/domain/errors/domain_errors.dart';
import 'package:hail_o_finance_core/domain/models/ride_event_type.dart';
import 'package:hail_o_finance_core/domain/services/escrow_service.dart';
import 'package:hail_o_finance_core/domain/services/ride_orchestrator_service.dart';
import 'package:hail_o_finance_core/domain/services/wallet_reversal_service.dart';

import 'sim_types.dart';

class ScenarioActions {
  ScenarioActions(this.db, {required DateTime Function() nowUtc})
    : _orchestrator = RideOrchestratorService(db, nowUtc: nowUtc),
      _escrowService = EscrowService(db, nowUtc: nowUtc),
      _walletReversalService = WalletReversalService(db, nowUtc: nowUtc),
      _nowUtc = nowUtc;

  final Database db;
  final DateTime Function() _nowUtc;
  final RideOrchestratorService _orchestrator;
  final EscrowService _escrowService;
  final WalletReversalService _walletReversalService;

  Future<Map<String, Object?>> runStep({
    required SimScenarioConfig config,
    required SimStepType stepType,
    required int stepIndex,
    required SeededRng rng,
  }) async {
    await _ensureScenarioUsers(config);

    final key = buildSimIdempotencyKey(
      seed: config.seed,
      scenarioId: config.scenarioId,
      stepIndex: stepIndex,
      stepType: stepType,
      entityIds: config.entityIds,
    );

    switch (stepType) {
      case SimStepType.bookRide:
        return _orchestrator.applyEvent(
          eventType: RideEventType.rideBooked,
          rideId: config.entityIds.rideId,
          idempotencyKey: key,
          actorId: config.entityIds.riderId,
          payload: <String, Object?>{
            'rider_id': config.entityIds.riderId,
            'trip_scope': 'intra_city',
            'distance_meters': 6000 + rng.nextInt(25000),
            'duration_seconds': 1200 + rng.nextInt(3600),
            'luggage_count': rng.nextInt(3),
            'vehicle_class': rng.chancePercent(75) ? 'sedan' : 'suv',
            'base_fare_minor': 10000 + rng.nextInt(8000),
            'premium_markup_minor': rng.nextInt(3000),
          },
        );
      case SimStepType.acceptRide:
        return _orchestrator.applyEvent(
          eventType: RideEventType.driverAccepted,
          rideId: config.entityIds.rideId,
          idempotencyKey: key,
          actorId: config.entityIds.driverId,
          payload: <String, Object?>{'driver_id': config.entityIds.driverId},
        );
      case SimStepType.acceptRideAltDriver:
        return _orchestrator.applyEvent(
          eventType: RideEventType.driverAccepted,
          rideId: config.entityIds.rideId,
          idempotencyKey: key,
          actorId: config.entityIds.altDriverId,
          payload: <String, Object?>{'driver_id': config.entityIds.altDriverId},
        );
      case SimStepType.startRide:
        return _orchestrator.applyEvent(
          eventType: RideEventType.rideStarted,
          rideId: config.entityIds.rideId,
          idempotencyKey: key,
          actorId: config.entityIds.driverId,
        );
      case SimStepType.completeRide:
        return _orchestrator.applyEvent(
          eventType: RideEventType.rideCompleted,
          rideId: config.entityIds.rideId,
          idempotencyKey: key,
          actorId: config.entityIds.driverId,
        );
      case SimStepType.cancelRide:
        return _orchestrator.applyEvent(
          eventType: RideEventType.rideCancelled,
          rideId: config.entityIds.rideId,
          idempotencyKey: key,
          actorId: config.entityIds.riderId,
          payload: <String, Object?>{
            'payer_user_id': config.entityIds.riderId,
            'penalty_minor': 0,
            'rule_code': 'sim_cancel_zero_penalty',
            'ride_type': 'intra',
          },
        );
      case SimStepType.settleRide:
        await _ensureEscrowHold(config);
        return _escrowService.releaseOnManualOverride(
          escrowId: config.entityIds.escrowId,
          riderId: config.entityIds.riderId,
          idempotencyKey: key,
          settlementIdempotencyKey: 'settlement:${config.entityIds.escrowId}',
        );
      case SimStepType.openDispute:
        return _orchestrator.applyEvent(
          eventType: RideEventType.disputeOpened,
          rideId: config.entityIds.rideId,
          idempotencyKey: key,
          actorId: config.entityIds.riderId,
          payload: <String, Object?>{
            'dispute_id': config.entityIds.disputeId,
            'opened_by': config.entityIds.riderId,
            'reason': 'simulated_issue',
          },
        );
      case SimStepType.resolveDispute:
        return _orchestrator.applyEvent(
          eventType: RideEventType.disputeResolved,
          rideId: config.entityIds.rideId,
          idempotencyKey: key,
          actorId: config.entityIds.adminId,
          payload: <String, Object?>{
            'dispute_id': config.entityIds.disputeId,
            'resolver_user_id': config.entityIds.adminId,
            'resolver_is_admin': true,
            'refund_minor': 0,
            'resolution_note': 'simulated_resolution',
          },
        );
      case SimStepType.reverseLatestCredit:
        final ledgerRows = await db.query(
          'wallet_ledger',
          columns: <String>['id', 'owner_id'],
          where: 'reference_id = ? AND direction = ?',
          whereArgs: <Object>[config.entityIds.rideId, 'credit'],
          orderBy: 'id DESC',
          limit: 1,
        );
        if (ledgerRows.isEmpty) {
          return <String, Object?>{
            'ok': true,
            'replayed': false,
            'skipped': true,
            'reason': 'no_credit_ledger_available',
          };
        }
        final originalLedgerId = (ledgerRows.first['id'] as num).toInt();
        return _walletReversalService.reverseWalletLedgerEntry(
          originalLedgerId: originalLedgerId,
          requestedByUserId: config.entityIds.adminId,
          requesterIsAdmin: true,
          reason: 'sim_reversal:${config.entityIds.rideId}',
          idempotencyKey: key,
        );
    }
  }

  Future<void> syncState({
    required SimScenarioConfig config,
    required SimMutableState state,
  }) async {
    final rideRows = await db.query(
      'rides',
      columns: <String>['status'],
      where: 'id = ?',
      whereArgs: <Object>[config.entityIds.rideId],
      limit: 1,
    );
    if (rideRows.isNotEmpty) {
      final status = (rideRows.first['status'] as String?) ?? '';
      state.booked = true;
      state.accepted =
          status == 'accepted' ||
          status == 'in_progress' ||
          status == 'completed' ||
          status == 'finance_settled';
      state.started =
          status == 'in_progress' ||
          status == 'completed' ||
          status == 'finance_settled';
      state.completed = status == 'completed' || status == 'finance_settled';
      state.cancelled = status == 'cancelled';
      state.settled = status == 'finance_settled';
    }

    final payoutRows = await db.query(
      'payout_records',
      where: 'escrow_id = ?',
      whereArgs: <Object>[config.entityIds.escrowId],
      limit: 1,
    );
    state.settled = state.settled || payoutRows.isNotEmpty;

    final disputeRows = await db.query(
      'disputes',
      where: 'id = ?',
      whereArgs: <Object>[config.entityIds.disputeId],
      limit: 1,
    );
    if (disputeRows.isNotEmpty) {
      state.disputeOpened = true;
      final status = (disputeRows.first['status'] as String?) ?? '';
      if (status == 'resolved') {
        state.disputeResolved = true;
      }
    }

    final reversalRows = await db.query(
      'wallet_reversals',
      columns: <String>['id'],
      limit: 1,
    );
    state.reversalApplied = reversalRows.isNotEmpty;
  }

  Future<void> _ensureScenarioUsers(SimScenarioConfig config) async {
    final nowIso = _nowUtc().toUtc().toIso8601String();
    await db.insert('users', <String, Object?>{
      'id': config.entityIds.riderId,
      'role': 'rider',
      'created_at': nowIso,
      'updated_at': nowIso,
    }, conflictAlgorithm: ConflictAlgorithm.ignore);
    await db.insert('users', <String, Object?>{
      'id': config.entityIds.driverId,
      'role': 'driver',
      'created_at': nowIso,
      'updated_at': nowIso,
    }, conflictAlgorithm: ConflictAlgorithm.ignore);
    await db.insert('users', <String, Object?>{
      'id': config.entityIds.altDriverId,
      'role': 'driver',
      'created_at': nowIso,
      'updated_at': nowIso,
    }, conflictAlgorithm: ConflictAlgorithm.ignore);
    await db.insert('users', <String, Object?>{
      'id': config.entityIds.adminId,
      'role': 'admin',
      'created_at': nowIso,
      'updated_at': nowIso,
    }, conflictAlgorithm: ConflictAlgorithm.ignore);
    await db.insert('next_of_kin', <String, Object?>{
      'user_id': config.entityIds.riderId,
      'full_name': 'Sim Kin',
      'phone': '+2347000000000',
      'relationship': 'relative',
      'created_at': nowIso,
      'updated_at': nowIso,
    }, conflictAlgorithm: ConflictAlgorithm.ignore);
  }

  Future<void> _ensureEscrowHold(SimScenarioConfig config) async {
    final existing = await db.query(
      'escrow_holds',
      columns: <String>['id'],
      where: 'id = ?',
      whereArgs: <Object>[config.entityIds.escrowId],
      limit: 1,
    );
    if (existing.isNotEmpty) {
      return;
    }
    final rideRows = await db.query(
      'rides',
      columns: <String>['total_fare_minor'],
      where: 'id = ?',
      whereArgs: <Object>[config.entityIds.rideId],
      limit: 1,
    );
    if (rideRows.isEmpty) {
      throw const DomainInvariantError(code: 'settle_without_booked_ride');
    }
    final amountMinor =
        (rideRows.first['total_fare_minor'] as num?)?.toInt() ?? 0;
    await db.insert('escrow_holds', <String, Object?>{
      'id': config.entityIds.escrowId,
      'ride_id': config.entityIds.rideId,
      'holder_user_id': config.entityIds.riderId,
      'amount_minor': amountMinor,
      'status': 'held',
      'created_at': _nowUtc().toUtc().toIso8601String(),
    }, conflictAlgorithm: ConflictAlgorithm.abort);
  }
}
