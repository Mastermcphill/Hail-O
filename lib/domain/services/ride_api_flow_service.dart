import 'package:hail_o_finance_core/sqlite_api.dart';
import 'package:uuid/uuid.dart';

import '../../data/sqlite/dao/escrow_holds_dao.dart';
import '../../data/sqlite/dao/rides_dao.dart';
import '../../data/sqlite/dao/ride_request_metadata_dao.dart';
import '../../data/sqlite/dao/users_dao.dart';
import '../errors/domain_errors.dart';
import '../models/escrow_hold.dart';
import '../models/ride_event_type.dart';
import '../models/ride_request_metadata.dart';
import '../models/ride_trip.dart';
import '../models/user.dart';
import 'accept_ride_service.dart';
import 'cancel_ride_service.dart';
import 'penalty_engine_service.dart';
import 'ride_orchestrator_service.dart';
import 'ride_settlement_service.dart';

enum ApiTripScope {
  intraCity('intra_city'),
  interState('inter_state'),
  crossCountry('cross_country'),
  international('international');

  const ApiTripScope(this.dbValue);

  final String dbValue;

  TripScope toTripScope() => TripScope.fromDbValue(dbValue);
}

class RideApiFlowService {
  RideApiFlowService(
    this.db, {
    RideOrchestratorService? rideOrchestratorService,
    AcceptRideService? acceptRideService,
    CancelRideService? cancelRideService,
    RideSettlementService? rideSettlementService,
    Uuid? uuid,
    DateTime Function()? nowUtc,
  }) : _rideOrchestratorService =
           rideOrchestratorService ?? RideOrchestratorService(db),
       _acceptRideService = acceptRideService ?? AcceptRideService(db),
       _cancelRideService = cancelRideService ?? CancelRideService(db),
       _rideSettlementService =
           rideSettlementService ?? RideSettlementService(db),
       _uuid = uuid ?? const Uuid(),
       _nowUtc = nowUtc ?? (() => DateTime.now().toUtc());

  final Database db;
  final RideOrchestratorService _rideOrchestratorService;
  final AcceptRideService _acceptRideService;
  final CancelRideService _cancelRideService;
  final RideSettlementService _rideSettlementService;
  final Uuid _uuid;
  final DateTime Function() _nowUtc;

  Future<Map<String, Object?>> requestRide({
    required String riderUserId,
    required ApiTripScope tripScope,
    required DateTime scheduledDepartureAtUtc,
    required int distanceMeters,
    required int durationSeconds,
    required int luggageCount,
    required String vehicleClass,
    required int baseFareMinor,
    required int premiumMarkupMinor,
    int connectionFeeMinor = 0,
    String? rideId,
    String? idempotencyKey,
  }) async {
    final resolvedRideId = (rideId?.trim().isNotEmpty ?? false)
        ? rideId!.trim()
        : _uuid.v4();
    final now = _nowUtc();

    final user = await UsersDao(db).findById(riderUserId);
    if (user == null) {
      throw const DomainInvariantError(code: 'rider_not_found');
    }
    if (user.role != UserRole.rider && user.role != UserRole.admin) {
      throw const UnauthorizedActionError(code: 'ride_request_forbidden');
    }

    final eventResult = await _rideOrchestratorService.applyEvent(
      eventType: RideEventType.rideBooked,
      rideId: resolvedRideId,
      idempotencyKey: idempotencyKey ?? 'ride_request:$resolvedRideId',
      actorId: riderUserId,
      payload: <String, Object?>{
        'rider_id': riderUserId,
        'trip_scope': tripScope.dbValue,
        'distance_meters': distanceMeters,
        'duration_seconds': durationSeconds,
        'luggage_count': luggageCount,
        'vehicle_class': vehicleClass,
        'base_fare_minor': baseFareMinor,
        'premium_markup_minor': premiumMarkupMinor,
        'connection_fee_minor': connectionFeeMinor,
      },
    );

    final quotedFareMinor = (eventResult['quoted_fare_minor'] as num?)?.toInt();
    await db.transaction((txn) async {
      final metadataDao = RideRequestMetadataDao(txn);
      await metadataDao.upsert(
        RideRequestMetadata(
          rideId: resolvedRideId,
          scheduledDepartureAt: scheduledDepartureAtUtc.toUtc(),
          createdAt: now,
          updatedAt: now,
        ),
      );

      await EscrowHoldsDao(txn).createHeldIfAbsent(
        EscrowHold(
          id: 'escrow:$resolvedRideId',
          rideId: resolvedRideId,
          holderUserId: riderUserId,
          amountMinor: quotedFareMinor ?? (baseFareMinor + premiumMarkupMinor),
          status: 'held',
          createdAt: now,
          idempotencyScope: 'ride_request_escrow',
          idempotencyKey: 'ride_request_escrow:$resolvedRideId',
        ),
        viaOrchestrator: true,
      );
    });

    return <String, Object?>{
      'ok': true,
      'ride_id': resolvedRideId,
      'escrow_id': 'escrow:$resolvedRideId',
      'trip_scope': tripScope.dbValue,
      ...eventResult,
    };
  }

  Future<Map<String, Object?>> acceptRide({
    required String rideId,
    required String driverId,
    required String idempotencyKey,
  }) {
    return _acceptRideService.acceptRide(
      rideId: rideId,
      driverId: driverId,
      idempotencyKey: idempotencyKey,
    );
  }

  Future<Map<String, Object?>> cancelRide({
    required String rideId,
    required String actorUserId,
    required String idempotencyKey,
  }) async {
    final rideRow = await RidesDao(db).findById(rideId);
    if (rideRow == null) {
      throw const DomainInvariantError(code: 'ride_not_found');
    }

    final scheduledDeparture = await RideRequestMetadataDao(
      db,
    ).findByRideId(rideId);
    final cancelledAt = _nowUtc();
    final fallbackDeparture = DateTime.parse(
      (rideRow['created_at'] as String?) ?? cancelledAt.toIso8601String(),
    ).toUtc();

    final totalFareMinor = (rideRow['total_fare_minor'] as num?)?.toInt() ?? 0;
    final rideType = _penaltyRideTypeForTripScope(
      (rideRow['trip_scope'] as String?) ?? TripScope.intraCity.dbValue,
    );
    PenaltyEngineService engine;
    try {
      engine = await PenaltyEngineService.fromDatabase(
        db,
        asOfUtc: cancelledAt,
        scope: rideType.dbValue,
        subjectId: rideId,
      );
    } catch (_) {
      engine = const PenaltyEngineService();
    }

    final computation = engine.computeCancellationPenaltyMinor(
      rideType: rideType,
      totalFareMinor: totalFareMinor,
      scheduledDeparture:
          scheduledDeparture?.scheduledDepartureAt ?? fallbackDeparture,
      cancelledAt: cancelledAt,
    );

    final result = await _cancelRideService.collectCancellationPenalty(
      rideId: rideId,
      payerUserId: actorUserId,
      penaltyMinor: computation.penaltyMinor,
      idempotencyKey: idempotencyKey,
      ruleCode: computation.ruleCode,
      rideType: rideType.dbValue,
      totalFareMinor: totalFareMinor,
      cancelledAt: cancelledAt,
    );
    return result.toMap();
  }

  Future<Map<String, Object?>> completeAndSettleRide({
    required String rideId,
    required String idempotencyKey,
    String? escrowId,
    SettlementTrigger trigger = SettlementTrigger.manualOverride,
  }) async {
    final completed = await _rideOrchestratorService.applyEvent(
      eventType: RideEventType.rideCompleted,
      rideId: rideId,
      idempotencyKey: idempotencyKey,
      payload: const <String, Object?>{},
    );

    final hold =
        await EscrowHoldsDao(db).findById(escrowId ?? '') ??
        await EscrowHoldsDao(db).findByRideId(rideId);
    if (hold == null) {
      return <String, Object?>{
        'ok': true,
        'ride_id': rideId,
        'completed': completed,
        'settlement': <String, Object?>{
          'ok': false,
          'error': 'escrow_not_found',
        },
      };
    }

    final settlement = await _rideSettlementService.settleOnEscrowRelease(
      escrowId: hold.id,
      rideId: rideId,
      idempotencyKey: 'settlement:${hold.id}',
      trigger: trigger,
    );
    return <String, Object?>{
      'ok': completed['ok'] == true && settlement.ok,
      'ride_id': rideId,
      'completed': completed,
      'settlement': settlement.toMap(),
    };
  }

  RideType _penaltyRideTypeForTripScope(String tripScope) {
    final normalized = tripScope.trim().toLowerCase();
    if (normalized == TripScope.interState.dbValue) {
      return RideType.inter;
    }
    if (normalized == TripScope.crossCountry.dbValue ||
        normalized == TripScope.international.dbValue) {
      return RideType.international;
    }
    return RideType.intra;
  }
}
