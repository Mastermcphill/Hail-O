import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:hail_o_finance_core/sqlite_api.dart';

import '../../data/sqlite/dao/idempotency_dao.dart';
import '../../data/sqlite/dao/ride_events_dao.dart';
import '../../data/sqlite/dao/rides_dao.dart';
import '../errors/domain_errors.dart';
import '../models/idempotency_record.dart';
import '../models/ride_event.dart';
import '../models/ride_event_type.dart';
import '../models/ride_trip.dart';
import '../observability/trace_context.dart';
import 'accept_ride_service.dart';
import 'cancel_ride_service.dart';
import 'dispute_service.dart';
import 'finance_utils.dart';
import 'pricing_engine_service.dart';
import 'ride_booking_service.dart';
import 'operation_journal_service.dart';
import 'ride_settlement_service.dart';

class RideOrchestratorService {
  RideOrchestratorService(
    this.db, {
    DateTime Function()? nowUtc,
    AcceptRideService? acceptRideService,
    CancelRideService? cancelRideService,
    RideSettlementService? rideSettlementService,
    DisputeService? disputeService,
    PricingEngineService? pricingEngineService,
    OperationJournalService? operationJournalService,
    void Function(RideEventType eventType)? faultHookAfterEventInsert,
  }) : _nowUtc = nowUtc ?? (() => DateTime.now().toUtc()),
       _acceptRideService =
           acceptRideService ?? AcceptRideService(db, nowUtc: nowUtc),
       _cancelRideService =
           cancelRideService ?? CancelRideService(db, nowUtc: nowUtc),
       _rideSettlementService =
           rideSettlementService ?? RideSettlementService(db, nowUtc: nowUtc),
       _disputeService = disputeService ?? DisputeService(db, nowUtc: nowUtc),
       _pricingEngineService =
           pricingEngineService ?? const PricingEngineService(),
       _idempotencyStore = IdempotencyDao(db),
       _operationJournalService =
           operationJournalService ??
           OperationJournalService(db, nowUtc: nowUtc),
       _faultHookAfterEventInsert = faultHookAfterEventInsert;

  final Database db;
  final DateTime Function() _nowUtc;
  final AcceptRideService _acceptRideService;
  final CancelRideService _cancelRideService;
  final RideSettlementService _rideSettlementService;
  final DisputeService _disputeService;
  final PricingEngineService _pricingEngineService;
  final IdempotencyStore _idempotencyStore;
  final OperationJournalService _operationJournalService;
  final void Function(RideEventType eventType)? _faultHookAfterEventInsert;

  static const String _scopeRideEvent = 'ride_event';

  Future<Map<String, Object?>> applyEvent({
    required RideEventType eventType,
    required String rideId,
    required String idempotencyKey,
    String? actorId,
    Map<String, Object?> payload = const <String, Object?>{},
    TraceContext? traceContext,
    bool includeDebug = false,
  }) async {
    if (idempotencyKey.trim().isEmpty) {
      throw ArgumentError('idempotencyKey is required');
    }

    final claim = await _idempotencyStore.claim(
      scope: _scopeRideEvent,
      key: idempotencyKey,
      requestHash: '$rideId|${eventType.dbValue}|${jsonEncode(payload)}',
    );
    final shouldRetryFailedClaim =
        !claim.isNewClaim && claim.record.status == IdempotencyStatus.failed;
    if (!claim.isNewClaim && !shouldRetryFailedClaim) {
      return _buildReplayResponse(
        claim.record,
        idempotencyKey: idempotencyKey,
        includeDebug: includeDebug,
        traceContext: traceContext,
      );
    }

    final traceId =
        traceContext?.traceId ?? 'trace:$_scopeRideEvent:$idempotencyKey';
    await _operationJournalService.begin(
      opType: _opTypeFor(eventType),
      entityType: 'ride',
      entityId: rideId,
      idempotencyScope: _scopeRideEvent,
      idempotencyKey: idempotencyKey,
      traceId: traceId,
      metadataJson: jsonEncode(payload),
    );

    try {
      final result = await _applyEventInternal(
        eventType: eventType,
        rideId: rideId,
        idempotencyKey: idempotencyKey,
        actorId: actorId,
        payload: payload,
      );
      final hash = sha256.convert(utf8.encode(jsonEncode(result))).toString();
      await _idempotencyStore.finalizeSuccess(
        scope: _scopeRideEvent,
        key: idempotencyKey,
        resultHash: hash,
      );
      await _operationJournalService.commit(
        idempotencyScope: _scopeRideEvent,
        idempotencyKey: idempotencyKey,
      );
      final out = <String, Object?>{...result, 'result_hash': hash};
      if (includeDebug) {
        out['debug'] = _debugMap(traceContext, idempotencyKey, rideId);
      }
      return out;
    } catch (e) {
      final code = e is DomainError ? e.code : 'ride_event_apply_exception';
      await _idempotencyStore.finalizeFailure(
        scope: _scopeRideEvent,
        key: idempotencyKey,
        errorCode: code,
      );
      await _operationJournalService.fail(
        idempotencyScope: _scopeRideEvent,
        idempotencyKey: idempotencyKey,
        errorMessage: _safeError(e),
      );
      rethrow;
    }
  }

  Future<Map<String, Object?>> _applyEventInternal({
    required RideEventType eventType,
    required String rideId,
    required String idempotencyKey,
    required String? actorId,
    required Map<String, Object?> payload,
  }) async {
    if (_isInternalTransitionEvent(eventType)) {
      return db.transaction((txn) async {
        await _insertRideEvent(
          txn,
          eventType: eventType,
          rideId: rideId,
          actorId: actorId,
          idempotencyKey: idempotencyKey,
          payload: payload,
        );
        _faultHookAfterEventInsert?.call(eventType);

        switch (eventType) {
          case RideEventType.rideBooked:
            return _bookRideOnExecutor(txn, rideId: rideId, payload: payload);
          case RideEventType.driverAccepted:
            return _acceptRideOnExecutor(
              txn,
              rideId: rideId,
              payload: payload,
              idempotencyKey: idempotencyKey,
            );
          case RideEventType.rideStarted:
            await RidesDao(txn).markStarted(
              rideId: rideId,
              startedAtIso: isoNowUtc(_nowUtc()),
              nowIso: isoNowUtc(_nowUtc()),
              viaOrchestrator: true,
            );
            return <String, Object?>{
              'ok': true,
              'ride_id': rideId,
              'event_type': eventType.dbValue,
              'status': 'in_progress',
            };
          case RideEventType.rideCompleted:
            await RidesDao(txn).markCompleted(
              rideId: rideId,
              completedAtIso: isoNowUtc(_nowUtc()),
              nowIso: isoNowUtc(_nowUtc()),
              viaOrchestrator: true,
            );
            return <String, Object?>{
              'ok': true,
              'ride_id': rideId,
              'event_type': eventType.dbValue,
              'status': 'completed',
            };
          case RideEventType.rideCancelled:
          case RideEventType.settled:
          case RideEventType.disputeOpened:
          case RideEventType.disputeResolved:
            throw const DomainInvariantError(code: 'unexpected_event_path');
        }
      });
    }

    await db.transaction((txn) async {
      await _insertRideEvent(
        txn,
        eventType: eventType,
        rideId: rideId,
        actorId: actorId,
        idempotencyKey: idempotencyKey,
        payload: payload,
      );
    });
    _faultHookAfterEventInsert?.call(eventType);

    switch (eventType) {
      case RideEventType.rideCancelled:
        return _cancelRide(
          rideId: rideId,
          payload: payload,
          idempotencyKey: idempotencyKey,
        );
      case RideEventType.settled:
        return _settleRide(
          rideId: rideId,
          payload: payload,
          idempotencyKey: idempotencyKey,
        );
      case RideEventType.disputeOpened:
        return _openDispute(
          rideId: rideId,
          payload: payload,
          idempotencyKey: idempotencyKey,
        );
      case RideEventType.disputeResolved:
        return _resolveDispute(
          rideId: rideId,
          payload: payload,
          idempotencyKey: idempotencyKey,
        );
      case RideEventType.rideBooked:
      case RideEventType.driverAccepted:
      case RideEventType.rideStarted:
      case RideEventType.rideCompleted:
        throw const DomainInvariantError(
          code: 'unexpected_internal_event_path',
        );
    }
  }

  Future<void> _insertRideEvent(
    DatabaseExecutor executor, {
    required RideEventType eventType,
    required String rideId,
    required String? actorId,
    required String idempotencyKey,
    required Map<String, Object?> payload,
  }) async {
    final now = _nowUtc();
    try {
      await RideEventsDao(executor).insert(
        RideEvent(
          id: 'ride_event:$rideId:${eventType.dbValue}:$idempotencyKey',
          rideId: rideId,
          eventType: eventType,
          actorId: actorId,
          idempotencyScope: _scopeRideEvent,
          idempotencyKey: idempotencyKey,
          payloadJson: jsonEncode(payload),
          createdAt: now,
        ),
      );
    } on DatabaseException {
      final existing = await RideEventsDao(executor).findByIdempotency(
        idempotencyScope: _scopeRideEvent,
        idempotencyKey: idempotencyKey,
      );
      if (existing == null) {
        rethrow;
      }
    }
  }

  Future<Map<String, Object?>> _bookRideOnExecutor(
    DatabaseExecutor executor, {
    required String rideId,
    required Map<String, Object?> payload,
  }) async {
    final riderId = (payload['rider_id'] as String?)?.trim() ?? '';
    if (riderId.isEmpty) {
      throw const DomainInvariantError(code: 'ride_booked_missing_rider');
    }
    final tripScopeRaw = (payload['trip_scope'] as String?) ?? 'intra_city';
    final tripScope = TripScope.fromDbValue(tripScopeRaw);
    final now = _nowUtc();
    final distanceMeters = (payload['distance_meters'] as num?)?.toInt() ?? 0;
    final durationSeconds = (payload['duration_seconds'] as num?)?.toInt() ?? 0;
    final luggageCount = (payload['luggage_count'] as num?)?.toInt() ?? 0;
    final vehicleClass = PricingVehicleClass.fromDbValue(
      (payload['vehicle_class'] as String?) ?? 'sedan',
    );
    PricingEngineService pricingEngine;
    try {
      pricingEngine = await PricingEngineService.fromDatabase(
        executor,
        asOfUtc: now,
        scope: tripScope.dbValue,
        subjectId: rideId,
      );
    } catch (_) {
      pricingEngine = _pricingEngineService;
    }

    final quote = pricingEngine.quote(
      tripScope: tripScope.dbValue,
      distanceMeters: distanceMeters,
      durationSeconds: durationSeconds,
      luggageCount: luggageCount,
      vehicleClass: vehicleClass,
      requestedAtUtc: now,
    );

    final ride = RideTrip(
      id: rideId,
      riderId: riderId,
      driverId: (payload['driver_id'] as String?)?.trim(),
      tripScope: tripScope,
      status: 'pending',
      baseFareMinor: (payload['base_fare_minor'] as num?)?.toInt() ?? 0,
      premiumMarkupMinor:
          (payload['premium_markup_minor'] as num?)?.toInt() ?? 0,
      charterMode: ((payload['charter_mode'] as num?)?.toInt() ?? 0) == 1,
      dailyRateMinor: (payload['daily_rate_minor'] as num?)?.toInt() ?? 0,
      totalFareMinor: quote.fareMinor,
      connectionFeeMinor:
          (payload['connection_fee_minor'] as num?)?.toInt() ?? 0,
      connectionFeePaid: false,
      biddingMode: true,
      pricingVersion: pricingEngine.ruleVersion,
      pricingBreakdownJson: quote.breakdownJson,
      quotedFareMinor: quote.fareMinor,
      createdAt: now,
      updatedAt: now,
    );

    await RideBookingService(executor).bookRide(ride);
    return <String, Object?>{
      'ok': true,
      'event_type': RideEventType.rideBooked.dbValue,
      'ride_id': rideId,
      'quoted_fare_minor': quote.fareMinor,
      'pricing_version': pricingEngine.ruleVersion,
      'status': 'pending',
    };
  }

  Future<Map<String, Object?>> _acceptRideOnExecutor(
    DatabaseExecutor executor, {
    required String rideId,
    required Map<String, Object?> payload,
    required String idempotencyKey,
  }) async {
    final driverId = (payload['driver_id'] as String?)?.trim() ?? '';
    if (driverId.isEmpty) {
      throw const DomainInvariantError(code: 'ride_accept_missing_driver');
    }
    final accepted = await _acceptRideService.acceptRideWithExecutor(
      executor,
      rideId: rideId,
      driverId: driverId,
      idempotencyKey: '$idempotencyKey:accept',
    );
    return <String, Object?>{
      ...accepted,
      'event_type': RideEventType.driverAccepted.dbValue,
    };
  }

  Future<Map<String, Object?>> _cancelRide({
    required String rideId,
    required Map<String, Object?> payload,
    required String idempotencyKey,
  }) async {
    final payerUserId = (payload['payer_user_id'] as String?)?.trim() ?? '';
    if (payerUserId.isEmpty) {
      throw const DomainInvariantError(code: 'ride_cancel_missing_payer');
    }
    final penaltyMinor = (payload['penalty_minor'] as num?)?.toInt() ?? 0;
    final ruleCode =
        (payload['rule_code'] as String?) ?? 'cancellation_penalty_assessed';
    final cancelled = await _cancelRideService.collectCancellationPenalty(
      rideId: rideId,
      payerUserId: payerUserId,
      penaltyMinor: penaltyMinor,
      idempotencyKey: '$idempotencyKey:cancel',
      ruleCode: ruleCode,
      rideType: payload['ride_type'] as String?,
      totalFareMinor: (payload['total_fare_minor'] as num?)?.toInt(),
      cancelledAt: _nowUtc(),
    );
    return <String, Object?>{
      ...cancelled.toMap(),
      'event_type': RideEventType.rideCancelled.dbValue,
    };
  }

  Future<Map<String, Object?>> _settleRide({
    required String rideId,
    required Map<String, Object?> payload,
    required String idempotencyKey,
  }) async {
    final escrowId = (payload['escrow_id'] as String?)?.trim() ?? '';
    if (escrowId.isEmpty) {
      throw const DomainInvariantError(code: 'settle_missing_escrow');
    }
    final triggerRaw = (payload['trigger'] as String?) ?? 'manual_override';
    final trigger = SettlementTrigger.fromDbValue(triggerRaw);
    final settlement = await _rideSettlementService.settleOnEscrowRelease(
      escrowId: escrowId,
      rideId: rideId,
      idempotencyKey: '$idempotencyKey:settle',
      trigger: trigger,
    );
    return <String, Object?>{
      ...settlement.toMap(),
      'event_type': RideEventType.settled.dbValue,
    };
  }

  Future<Map<String, Object?>> _openDispute({
    required String rideId,
    required Map<String, Object?> payload,
    required String idempotencyKey,
  }) async {
    final disputeId =
        (payload['dispute_id'] as String?)?.trim().isNotEmpty == true
        ? (payload['dispute_id'] as String).trim()
        : 'dispute:$rideId';
    final openedBy = (payload['opened_by'] as String?)?.trim() ?? '';
    final reason = (payload['reason'] as String?) ?? 'unspecified';
    if (openedBy.isEmpty) {
      throw const DomainInvariantError(code: 'dispute_missing_opened_by');
    }
    final opened = await _disputeService.openDispute(
      disputeId: disputeId,
      rideId: rideId,
      openedBy: openedBy,
      reason: reason,
      idempotencyKey: '$idempotencyKey:open_dispute',
    );
    return <String, Object?>{
      ...opened,
      'event_type': RideEventType.disputeOpened.dbValue,
    };
  }

  Future<Map<String, Object?>> _resolveDispute({
    required String rideId,
    required Map<String, Object?> payload,
    required String idempotencyKey,
  }) async {
    final disputeId = (payload['dispute_id'] as String?)?.trim() ?? '';
    final resolverUserId =
        (payload['resolver_user_id'] as String?)?.trim() ?? '';
    final resolverIsAdmin = (payload['resolver_is_admin'] as bool?) ?? false;
    final refundMinor = (payload['refund_minor'] as num?)?.toInt() ?? 0;
    if (disputeId.isEmpty || resolverUserId.isEmpty) {
      throw const DomainInvariantError(code: 'dispute_resolve_missing_fields');
    }
    final resolved = await _disputeService.resolveDispute(
      disputeId: disputeId,
      resolverUserId: resolverUserId,
      resolverIsAdmin: resolverIsAdmin,
      refundMinor: refundMinor,
      idempotencyKey: '$idempotencyKey:resolve_dispute',
      resolutionNote: (payload['resolution_note'] as String?) ?? 'resolved',
    );
    return <String, Object?>{
      ...resolved,
      'ride_id': rideId,
      'event_type': RideEventType.disputeResolved.dbValue,
    };
  }

  bool _isInternalTransitionEvent(RideEventType eventType) {
    return eventType == RideEventType.rideBooked ||
        eventType == RideEventType.driverAccepted ||
        eventType == RideEventType.rideStarted ||
        eventType == RideEventType.rideCompleted;
  }

  String _opTypeFor(RideEventType eventType) {
    switch (eventType) {
      case RideEventType.rideBooked:
        return 'BOOK';
      case RideEventType.driverAccepted:
        return 'ACCEPT';
      case RideEventType.rideStarted:
        return 'START';
      case RideEventType.rideCompleted:
        return 'COMPLETE';
      case RideEventType.rideCancelled:
        return 'CANCEL';
      case RideEventType.settled:
        return 'SETTLE';
      case RideEventType.disputeOpened:
        return 'DISPUTE_OPEN';
      case RideEventType.disputeResolved:
        return 'DISPUTE_RESOLVE';
    }
  }

  Future<Map<String, Object?>> _buildReplayResponse(
    IdempotencyRecord record, {
    required String idempotencyKey,
    required bool includeDebug,
    required TraceContext? traceContext,
  }) async {
    final event = await RideEventsDao(db).findByIdempotency(
      idempotencyScope: _scopeRideEvent,
      idempotencyKey: idempotencyKey,
    );
    final response = <String, Object?>{
      'ok': record.status == IdempotencyStatus.success,
      'replayed': true,
      'result_hash': record.resultHash,
      'error': record.errorCode,
      'event': event?.toMap(),
    };
    if (includeDebug) {
      final rideId = event?.rideId;
      response['debug'] = _debugMap(traceContext, idempotencyKey, rideId);
    }
    return response;
  }

  Map<String, Object?> _debugMap(
    TraceContext? traceContext,
    String idempotencyKey,
    String? rideId,
  ) {
    return <String, Object?>{
      'trace': traceContext?.toMap(),
      'idempotency_scope': _scopeRideEvent,
      'idempotency_key': idempotencyKey,
      'ride_id': rideId,
    };
  }

  String _safeError(Object error) {
    final text = error.toString().trim();
    if (text.isEmpty) {
      return 'ride_orchestrator_unknown_error';
    }
    if (text.length > 500) {
      return text.substring(0, 500);
    }
    return text;
  }
}
