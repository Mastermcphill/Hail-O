import 'package:shelf/shelf.dart';
import 'package:shelf_router/shelf_router.dart';
import 'package:sqflite_common/sqlite_api.dart';
import 'package:uuid/uuid.dart';

import '../../../lib/data/sqlite/dao/rides_dao.dart';
import '../../../lib/domain/errors/domain_errors.dart';
import '../../../lib/domain/services/ride_api_flow_service.dart';
import '../../../lib/domain/services/ride_settlement_service.dart';
import '../../../lib/domain/services/ride_snapshot_service.dart';
import '../../../lib/services/wallet_service.dart';
import '../../infra/request_context.dart';
import '../../server/http_utils.dart';

class RidesController {
  RidesController({
    required Database db,
    required RideApiFlowService rideApiFlowService,
    required RideSnapshotService rideSnapshotService,
    WalletService? walletService,
    Uuid? uuid,
    DateTime Function()? nowUtc,
  }) : _db = db,
       _rideApiFlowService = rideApiFlowService,
       _rideSnapshotService = rideSnapshotService,
       _walletService = walletService ?? WalletService(db),
       _uuid = uuid ?? const Uuid(),
       _nowUtc = nowUtc ?? (() => DateTime.now().toUtc());

  final Database _db;
  final RideApiFlowService _rideApiFlowService;
  final RideSnapshotService _rideSnapshotService;
  final WalletService _walletService;
  final Uuid _uuid;
  final DateTime Function() _nowUtc;

  Router get router {
    final router = Router();
    router.post('/request', _requestRide);
    router.post('/<rideId>/accept', _acceptRide);
    router.post('/<rideId>/start', _startRide);
    router.post('/<rideId>/cancel', _cancelRide);
    router.post('/<rideId>/complete', _completeRide);

    router.get('/<rideId>/offers', _listOffers);
    router.post('/<rideId>/offers', _submitOffer);
    router.post('/<rideId>/accept-offer', _acceptOffer);
    router.post('/<rideId>/paywall/open', _openPaywall);
    router.post('/<rideId>/paywall/pay', _payPaywall);
    router.get('/<rideId>/seats', _getSeats);
    router.post('/<rideId>/seats/select', _selectSeats);

    router.get('/<rideId>', _getRideSnapshot);
    return router;
  }

  Future<Response> _requestRide(Request request) async {
    _requireRole(request, const <String>{'rider', 'admin'});
    final body = await readJsonBody(request);
    final riderId = request.requestContext.userId ?? '';
    if (riderId.isEmpty) {
      throw const UnauthorizedActionError(code: 'missing_user_context');
    }

    final scheduledRaw = (body['scheduled_departure_at'] as String?)?.trim();
    if (scheduledRaw == null || scheduledRaw.isEmpty) {
      throw const DomainInvariantError(code: 'scheduled_departure_required');
    }
    final scheduledDeparture = DateTime.parse(scheduledRaw).toUtc();

    final tripScope = _tripScopeFromRaw(
      (body['trip_scope'] as String?) ?? ApiTripScope.intraCity.dbValue,
    );

    final result = await _rideApiFlowService.requestRide(
      riderUserId: riderId,
      tripScope: tripScope,
      scheduledDepartureAtUtc: scheduledDeparture,
      distanceMeters: (body['distance_meters'] as num?)?.toInt() ?? 0,
      durationSeconds: (body['duration_seconds'] as num?)?.toInt() ?? 0,
      luggageCount: (body['luggage_count'] as num?)?.toInt() ?? 0,
      vehicleClass:
          (body['vehicle_class'] as String?)?.trim().toLowerCase() ?? 'sedan',
      baseFareMinor: (body['base_fare_minor'] as num?)?.toInt() ?? 0,
      premiumMarkupMinor: (body['premium_markup_minor'] as num?)?.toInt() ?? 0,
      connectionFeeMinor: (body['connection_fee_minor'] as num?)?.toInt() ?? 0,
      charterMode: _asBool(body['charter_mode']),
      dailyRateMinor: (body['daily_rate_minor'] as num?)?.toInt() ?? 0,
      rideId: (body['ride_id'] as String?)?.trim(),
      idempotencyKey: request.requestContext.idempotencyKey,
    );

    return jsonResponse(201, result);
  }

  Future<Response> _acceptRide(Request request, String rideId) async {
    _requireRole(request, const <String>{'driver', 'admin'});
    final body = await readJsonBody(request);
    final userRole = request.requestContext.role ?? '';
    final ctxUserId = request.requestContext.userId ?? '';
    final driverId = userRole == 'admin'
        ? ((body['driver_id'] as String?)?.trim() ?? '')
        : ctxUserId;
    if (driverId.isEmpty) {
      throw const DomainInvariantError(code: 'driver_id_required');
    }

    final result = await _rideApiFlowService.acceptRide(
      rideId: rideId,
      driverId: driverId,
      idempotencyKey: request.requestContext.idempotencyKey ?? '',
    );
    return jsonResponse(200, result);
  }

  Future<Response> _cancelRide(Request request, String rideId) async {
    _requireRole(request, const <String>{'rider', 'driver', 'admin'});
    final actorId = request.requestContext.userId ?? '';
    if (actorId.isEmpty) {
      throw const UnauthorizedActionError(code: 'missing_user_context');
    }

    final result = await _rideApiFlowService.cancelRide(
      rideId: rideId,
      actorUserId: actorId,
      idempotencyKey: request.requestContext.idempotencyKey ?? '',
    );
    return jsonResponse(200, result);
  }

  Future<Response> _startRide(Request request, String rideId) async {
    _requireRole(request, const <String>{'driver', 'admin'});
    final actorId = request.requestContext.userId ?? '';
    if (actorId.isEmpty) {
      throw const UnauthorizedActionError(code: 'missing_user_context');
    }

    final result = await _rideApiFlowService.startRide(
      rideId: rideId,
      actorUserId: actorId,
      idempotencyKey: request.requestContext.idempotencyKey ?? '',
    );
    return jsonResponse(200, result);
  }

  Future<Response> _completeRide(Request request, String rideId) async {
    _requireRole(request, const <String>{'driver', 'admin'});
    final body = await readJsonBody(request);

    final settlementTrigger = SettlementTrigger.fromDbValue(
      (body['settlement_trigger'] as String?) ?? 'manual_override',
    );
    final result = await _rideApiFlowService.completeAndSettleRide(
      rideId: rideId,
      idempotencyKey: request.requestContext.idempotencyKey ?? '',
      escrowId: (body['escrow_id'] as String?)?.trim(),
      trigger: settlementTrigger,
    );
    return jsonResponse(200, result);
  }

  Future<Response> _submitOffer(Request request, String rideId) async {
    _requireRole(request, const <String>{'driver', 'admin'});
    final body = await readJsonBody(request);
    final ride = await _findRideOrThrow(rideId);
    final rideStatus = ((ride['status'] as String?) ?? '').trim().toLowerCase();
    if (_isTerminalRideStatus(rideStatus)) {
      throw const DomainInvariantError(code: 'ride_not_open_for_offers');
    }

    final requestRole = (request.requestContext.role ?? '')
        .trim()
        .toLowerCase();
    final contextUserId = (request.requestContext.userId ?? '').trim();
    final adminDriverId = (body['driver_id'] as String?)?.trim() ?? '';
    final driverId = requestRole == 'admin' ? adminDriverId : contextUserId;
    if (driverId.isEmpty) {
      throw const DomainInvariantError(code: 'driver_id_required');
    }

    final offeredFareMinor =
        _asInt(body['price_minor'], fallback: null) ??
        _asInt(body['offered_fare_minor'], fallback: null) ??
        0;
    if (offeredFareMinor <= 0) {
      throw const DomainInvariantError(code: 'offer_price_required');
    }

    final nowIso = _nowUtc().toUtc().toIso8601String();
    final idempotencyKey = (request.requestContext.idempotencyKey ?? '').trim();
    final providedOfferId = (body['offer_id'] as String?)?.trim() ?? '';
    final offerId = providedOfferId.isNotEmpty
        ? providedOfferId
        : 'offer:$rideId:$idempotencyKey';

    final insertedRowId = await _db.insert('bids_offers', <String, Object?>{
      'id': offerId,
      'ride_id': rideId,
      'rider_id': (ride['rider_id'] as String?) ?? '',
      'driver_id': driverId,
      'offered_fare_minor': offeredFareMinor,
      'status': 'pending',
      'accepted_at': null,
      'created_at': nowIso,
      'updated_at': nowIso,
    }, conflictAlgorithm: ConflictAlgorithm.ignore);

    final rows = await _db.query(
      'bids_offers',
      where: 'id = ?',
      whereArgs: <Object>[offerId],
      limit: 1,
    );
    if (rows.isEmpty) {
      throw const DomainInvariantError(code: 'offer_persist_failed');
    }
    final payload = await _offerPayloadFromRow(rows.first);
    return jsonResponse(insertedRowId == 0 ? 200 : 201, <String, Object?>{
      'ok': true,
      'offer': payload,
    });
  }

  Future<Response> _listOffers(Request request, String rideId) async {
    _requireAuthenticated(request);
    await _findRideOrThrow(rideId);
    final rows = await _db.query(
      'bids_offers',
      where: 'ride_id = ? AND status IN (?, ?)',
      whereArgs: <Object>[rideId, 'pending', 'accepted'],
      orderBy: "CASE status WHEN 'accepted' THEN 0 ELSE 1 END, created_at ASC",
    );
    final offers = <Map<String, Object?>>[];
    for (final row in rows) {
      offers.add(await _offerPayloadFromRow(row));
    }
    return jsonResponse(200, <String, Object?>{'ok': true, 'offers': offers});
  }

  Future<Response> _acceptOffer(Request request, String rideId) async {
    _requireRole(request, const <String>{'rider', 'admin'});
    final ride = await _findRideOrThrow(rideId);
    _assertRideOwnedByRiderUnlessAdmin(request, ride);

    final body = await readJsonBody(request);
    final offerId = (body['offer_id'] as String?)?.trim() ?? '';
    if (offerId.isEmpty) {
      throw const DomainInvariantError(code: 'offer_id_required');
    }

    final offerRows = await _db.query(
      'bids_offers',
      where: 'id = ? AND ride_id = ?',
      whereArgs: <Object>[offerId, rideId],
      limit: 1,
    );
    if (offerRows.isEmpty) {
      throw const DomainInvariantError(code: 'offer_not_found');
    }
    final offer = offerRows.first;
    final offerStatus = ((offer['status'] as String?) ?? '')
        .trim()
        .toLowerCase();
    if (offerStatus != 'pending' && offerStatus != 'accepted') {
      throw const DomainInvariantError(code: 'offer_not_open');
    }

    final now = _nowUtc();
    final nowIso = now.toIso8601String();
    final deadlineIso = now
        .add(const Duration(minutes: 10))
        .toUtc()
        .toIso8601String();
    final connectionFeeMinor = _connectionFeeForRide(ride);
    final offeredFareMinor =
        (offer['offered_fare_minor'] as num?)?.toInt() ?? 0;

    await _db.transaction((txn) async {
      await txn.update(
        'bids_offers',
        <String, Object?>{'status': 'rejected', 'updated_at': nowIso},
        where: 'ride_id = ? AND id != ? AND status = ?',
        whereArgs: <Object>[rideId, offerId, 'pending'],
      );

      await txn.update(
        'bids_offers',
        <String, Object?>{
          'status': 'accepted',
          'accepted_at': nowIso,
          'updated_at': nowIso,
        },
        where: 'id = ?',
        whereArgs: <Object>[offerId],
      );

      final keepPaid = _isConnectionFeePaid(ride);
      await txn.update(
        'rides',
        <String, Object?>{
          'driver_id': (offer['driver_id'] as String?) ?? '',
          'status': keepPaid
              ? 'connection_fee_paid'
              : 'awaiting_connection_fee',
          'total_fare_minor': offeredFareMinor,
          'connection_fee_minor': connectionFeeMinor,
          'connection_fee_paid': keepPaid ? 1 : 0,
          'bid_accepted_at': nowIso,
          'connection_fee_deadline_at':
              (ride['connection_fee_deadline_at'] as String?) ?? deadlineIso,
          if (!keepPaid) 'connection_fee_paid_at': null,
          'updated_at': nowIso,
        },
        where: 'id = ?',
        whereArgs: <Object>[rideId],
      );
    });

    final refreshedOfferRows = await _db.query(
      'bids_offers',
      where: 'id = ?',
      whereArgs: <Object>[offerId],
      limit: 1,
    );
    final offerPayload = refreshedOfferRows.isEmpty
        ? <String, Object?>{
            'offer_id': offerId,
            'driver_id': (offer['driver_id'] as String?) ?? '',
            'price_minor': offeredFareMinor,
          }
        : await _offerPayloadFromRow(refreshedOfferRows.first);

    return jsonResponse(200, <String, Object?>{
      'ok': true,
      'ride_id': rideId,
      'offer': offerPayload,
      'connection_fee_minor': connectionFeeMinor,
      'deadline_at':
          (ride['connection_fee_deadline_at'] as String?) ?? deadlineIso,
    });
  }

  Future<Response> _openPaywall(Request request, String rideId) async {
    _requireRole(request, const <String>{'rider', 'admin'});
    final ride = await _findRideOrThrow(rideId);
    _assertRideOwnedByRiderUnlessAdmin(request, ride);

    final driverId = (ride['driver_id'] as String?)?.trim() ?? '';
    if (driverId.isEmpty) {
      throw const DomainInvariantError(code: 'offer_not_accepted');
    }

    var refreshedRide = ride;
    var deadline = _parseUtc(ride['connection_fee_deadline_at']);
    if (deadline == null) {
      deadline = _nowUtc().add(const Duration(minutes: 10)).toUtc();
      final nowIso = _nowUtc().toUtc().toIso8601String();
      await _db.update(
        'rides',
        <String, Object?>{
          'status': _isConnectionFeePaid(ride)
              ? 'connection_fee_paid'
              : 'awaiting_connection_fee',
          'connection_fee_deadline_at': deadline.toIso8601String(),
          'updated_at': nowIso,
        },
        where: 'id = ?',
        whereArgs: <Object>[rideId],
      );
      refreshedRide = await _findRideOrThrow(rideId);
    }

    final now = _nowUtc().toUtc();
    final connectionFeePaid = _isConnectionFeePaid(refreshedRide);
    final expired = !connectionFeePaid && now.isAfter(deadline);

    return jsonResponse(200, <String, Object?>{
      'ok': true,
      'ride_id': rideId,
      'connection_fee_minor': _connectionFeeForRide(refreshedRide),
      'deadline_at': deadline.toIso8601String(),
      'expired': expired,
      'connection_fee_paid': connectionFeePaid,
      'status': (refreshedRide['status'] as String?) ?? 'unknown',
    });
  }

  Future<Response> _payPaywall(Request request, String rideId) async {
    _requireRole(request, const <String>{'rider', 'admin'});
    final ride = await _findRideOrThrow(rideId);
    _assertRideOwnedByRiderUnlessAdmin(request, ride);
    final idempotencyKey = (request.requestContext.idempotencyKey ?? '').trim();
    if (idempotencyKey.isEmpty) {
      throw const DomainInvariantError(code: 'idempotency_key_required');
    }

    final result = await _walletService.payConnectionFee(
      rideId: rideId,
      idempotencyKey: idempotencyKey,
    );
    if (result['ok'] != true) {
      final errorCode = (result['error'] as String?)?.trim().isNotEmpty == true
          ? (result['error'] as String).trim()
          : 'connection_fee_payment_failed';
      return jsonResponse(200, <String, Object?>{
        'ok': false,
        'error_code': errorCode,
        'message': errorCode,
        'ride_id': rideId,
      });
    }

    final refreshedRide = await RidesDao(_db).findById(rideId);
    return jsonResponse(200, <String, Object?>{
      ...result,
      'status': (refreshedRide?['status'] as String?) ?? 'connection_fee_paid',
      'connection_fee_paid': refreshedRide == null
          ? false
          : _isConnectionFeePaid(refreshedRide),
    });
  }

  Future<Response> _getSeats(Request request, String rideId) async {
    _requireRole(request, const <String>{'rider', 'admin'});
    final ride = await _findRideOrThrow(rideId);
    _assertRideOwnedByRiderUnlessAdmin(request, ride);

    final seats = await _ensureSeatRowsForRide(ride);
    final requesterUserId = (request.requestContext.userId ?? '').trim();
    final payload = seats
        .map((seat) {
          final passengerUserId = (seat['passenger_user_id'] as String?)
              ?.trim();
          final seatCode = (seat['seat_code'] as String?) ?? 'back_left';
          return <String, Object?>{
            'seat_id': _seatIdFromCode(seatCode),
            'seat_code': seatCode,
            'seat_type': (seat['seat_type'] as String?) ?? 'middle',
            'base_fare_minor': (seat['base_fare_minor'] as num?)?.toInt() ?? 0,
            'markup_minor': (seat['markup_minor'] as num?)?.toInt() ?? 0,
            'available': passengerUserId == null || passengerUserId.isEmpty,
            'selected':
                requesterUserId.isNotEmpty &&
                passengerUserId != null &&
                passengerUserId == requesterUserId,
          };
        })
        .toList(growable: false);

    final basePriceMinor = seats.isEmpty
        ? _defaultSeatBaseFareMinor(ride)
        : (seats.first['base_fare_minor'] as num?)?.toInt() ?? 0;
    final dailyRateMinor = _dailyRateForRide(
      ride,
      basePriceMinor * (seats.isEmpty ? 4 : seats.length),
    );

    return jsonResponse(200, <String, Object?>{
      'ok': true,
      'ride_id': rideId,
      'seats': payload,
      'base_price_minor': basePriceMinor,
      'daily_rate_minor': dailyRateMinor,
      'charter_mode': _asBool(ride['charter_mode']),
    });
  }

  Future<Response> _selectSeats(Request request, String rideId) async {
    _requireRole(request, const <String>{'rider', 'admin'});
    final body = await readJsonBody(request);
    final ride = await _findRideOrThrow(rideId);
    _assertRideOwnedByRiderUnlessAdmin(request, ride);

    if (!_isConnectionFeePaid(ride)) {
      throw const DomainInvariantError(code: 'connection_fee_required');
    }

    final role = (request.requestContext.role ?? '').trim().toLowerCase();
    final contextUserId = (request.requestContext.userId ?? '').trim();
    final riderId = role == 'admin'
        ? ((body['rider_id'] as String?)?.trim().isNotEmpty == true
              ? (body['rider_id'] as String).trim()
              : ((ride['rider_id'] as String?)?.trim() ?? ''))
        : contextUserId;
    if (riderId.isEmpty) {
      throw const DomainInvariantError(code: 'rider_id_required');
    }

    final seats = await _ensureSeatRowsForRide(ride);
    if (seats.isEmpty) {
      throw const DomainInvariantError(code: 'seat_inventory_not_initialized');
    }

    final allSeatCodes = seats
        .map((seat) => (seat['seat_code'] as String?) ?? '')
        .where((code) => code.isNotEmpty)
        .toList(growable: false);
    var selectedCodes = _selectedSeatCodesFromBody(body['seat_ids']);
    final charterModeRequested =
        _asBool(body['charter_mode']) ||
        selectedCodes.length == allSeatCodes.length;
    if (charterModeRequested) {
      selectedCodes = allSeatCodes.toSet().toList(growable: false);
    }
    if (selectedCodes.isEmpty) {
      throw const DomainInvariantError(code: 'seat_ids_required');
    }

    final seatByCode = <String, Map<String, Object?>>{
      for (final seat in seats) (seat['seat_code'] as String?) ?? '': seat,
    };
    for (final code in selectedCodes) {
      final seat = seatByCode[code];
      if (seat == null) {
        throw const DomainInvariantError(code: 'seat_not_found');
      }
      final passenger = (seat['passenger_user_id'] as String?)?.trim();
      if (passenger != null && passenger.isNotEmpty && passenger != riderId) {
        throw const DomainInvariantError(code: 'seat_not_available');
      }
    }

    final nowIso = _nowUtc().toUtc().toIso8601String();
    final selectedSeatMaps = selectedCodes
        .map((code) => seatByCode[code])
        .whereType<Map<String, Object?>>()
        .toList(growable: false);
    final baseTotalMinor = selectedSeatMaps.fold<int>(
      0,
      (sum, seat) => sum + ((seat['base_fare_minor'] as num?)?.toInt() ?? 0),
    );
    final markupTotalMinor = selectedSeatMaps.fold<int>(
      0,
      (sum, seat) => sum + ((seat['markup_minor'] as num?)?.toInt() ?? 0),
    );
    final fallbackDailyRateMinor =
        _defaultSeatBaseFareMinor(ride) * seats.length;
    final dailyRateMinor = _dailyRateForRide(ride, fallbackDailyRateMinor);
    final pricingMinor = charterModeRequested
        ? dailyRateMinor
        : baseTotalMinor + markupTotalMinor;

    await _db.transaction((txn) async {
      for (final seat in seats) {
        final seatId = (seat['id'] as String?) ?? '';
        final seatCode = (seat['seat_code'] as String?) ?? '';
        if (seatId.isEmpty || seatCode.isEmpty) {
          continue;
        }
        final isSelected = selectedCodes.contains(seatCode);
        final existingPassenger = (seat['passenger_user_id'] as String?)
            ?.trim();
        if (isSelected) {
          await txn.update(
            'seats',
            <String, Object?>{
              'passenger_user_id': riderId,
              'assignment_locked': 1,
              'updated_at': nowIso,
            },
            where: 'id = ?',
            whereArgs: <Object>[seatId],
          );
          continue;
        }
        if (existingPassenger == riderId) {
          await txn.update(
            'seats',
            <String, Object?>{'passenger_user_id': null, 'updated_at': nowIso},
            where: 'id = ?',
            whereArgs: <Object>[seatId],
          );
        }
      }

      await txn.update(
        'rides',
        <String, Object?>{
          'base_fare_minor': charterModeRequested
              ? pricingMinor
              : baseTotalMinor,
          'premium_markup_minor': charterModeRequested ? 0 : markupTotalMinor,
          'charter_mode': charterModeRequested ? 1 : 0,
          'daily_rate_minor': dailyRateMinor,
          'total_fare_minor': pricingMinor,
          'updated_at': nowIso,
        },
        where: 'id = ?',
        whereArgs: <Object>[rideId],
      );

      await txn.delete(
        'manifests',
        where: 'ride_id = ? AND rider_id = ?',
        whereArgs: <Object>[rideId, riderId],
      );
      for (final seatCode in selectedCodes) {
        await txn.insert('manifests', <String, Object?>{
          'id': 'manifest:$rideId:$riderId:$seatCode',
          'ride_id': rideId,
          'rider_id': riderId,
          'seat_id': _seatIdFromCode(seatCode),
          'status': 'confirmed',
          'no_kin_valid': 1,
          'doc_valid': 1,
          'created_at': nowIso,
          'updated_at': nowIso,
        }, conflictAlgorithm: ConflictAlgorithm.replace);
      }
    });

    final idempotencyKey = (request.requestContext.idempotencyKey ?? '').trim();
    final purchaseId = idempotencyKey.isEmpty
        ? 'purchase:$rideId:${_uuid.v4()}'
        : 'purchase:$rideId:$idempotencyKey';
    final selectedSeatIds = selectedCodes
        .map(_seatIdFromCode)
        .toList(growable: false);

    return jsonResponse(200, <String, Object?>{
      'ok': true,
      'purchase_id': purchaseId,
      'ride_id': rideId,
      'seat_ids': selectedSeatIds,
      'pricing_minor': pricingMinor,
      'base_fare_minor': charterModeRequested ? pricingMinor : baseTotalMinor,
      'premium_markup_minor': charterModeRequested ? 0 : markupTotalMinor,
      'charter_mode': charterModeRequested,
      'daily_rate_minor': dailyRateMinor,
    });
  }

  Future<Response> _getRideSnapshot(Request request, String rideId) async {
    _requireAuthenticated(request);
    final snapshot = await _rideSnapshotService.getRideSnapshot(rideId);
    if (snapshot['ok'] != true) {
      return jsonErrorResponse(
        request,
        404,
        code: 'ride_not_found',
        message: (snapshot['error'] as String?) ?? 'ride_not_found',
      );
    }
    return jsonResponse(200, snapshot);
  }

  ApiTripScope _tripScopeFromRaw(String raw) {
    final normalized = raw.trim().toLowerCase();
    for (final scope in ApiTripScope.values) {
      if (scope.dbValue == normalized) {
        return scope;
      }
    }
    return ApiTripScope.intraCity;
  }

  Future<Map<String, Object?>> _findRideOrThrow(String rideId) async {
    final ride = await RidesDao(_db).findById(rideId);
    if (ride == null) {
      throw const DomainInvariantError(code: 'ride_not_found');
    }
    return ride;
  }

  void _assertRideOwnedByRiderUnlessAdmin(
    Request request,
    Map<String, Object?> ride,
  ) {
    final role = (request.requestContext.role ?? '').trim().toLowerCase();
    if (role == 'admin') {
      return;
    }
    final riderId = (ride['rider_id'] as String?)?.trim() ?? '';
    final userId = (request.requestContext.userId ?? '').trim();
    if (role != 'rider' || userId.isEmpty || riderId != userId) {
      throw const UnauthorizedActionError(code: 'forbidden');
    }
  }

  Future<Map<String, Object?>> _offerPayloadFromRow(
    Map<String, Object?> row,
  ) async {
    final driverId = (row['driver_id'] as String?)?.trim() ?? '';
    final userRows = await _db.query(
      'users',
      columns: <String>['star_rating', 'gender', 'tribe'],
      where: 'id = ?',
      whereArgs: <Object>[driverId],
      limit: 1,
    );
    final vehicleRows = await _db.query(
      'vehicles',
      columns: <String>['type'],
      where: 'driver_id = ? AND is_active = 1',
      whereArgs: <Object>[driverId],
      orderBy: 'created_at DESC',
      limit: 1,
    );
    final user = userRows.isEmpty ? const <String, Object?>{} : userRows.first;
    final vehicleClass = vehicleRows.isEmpty
        ? 'sedan'
        : (vehicleRows.first['type'] as String?)?.trim().toLowerCase() ??
              'sedan';

    return <String, Object?>{
      'offer_id': (row['id'] as String?) ?? '',
      'ride_id': (row['ride_id'] as String?) ?? '',
      'driver_id': driverId,
      'price_minor': (row['offered_fare_minor'] as num?)?.toInt() ?? 0,
      'star_rating': (user['star_rating'] as num?)?.toDouble() ?? 0,
      'gender': (user['gender'] as String?)?.trim().isNotEmpty == true
          ? (user['gender'] as String).trim()
          : 'undisclosed',
      'tribe': (user['tribe'] as String?)?.trim(),
      'vehicle_class': vehicleClass,
      'luggage_supported': vehicleClass == 'suv' || vehicleClass == 'bus',
      'status': (row['status'] as String?) ?? 'pending',
      'accepted_at': row['accepted_at'] as String?,
    };
  }

  Future<List<Map<String, Object?>>> _ensureSeatRowsForRide(
    Map<String, Object?> ride,
  ) async {
    final rideId = (ride['id'] as String?) ?? '';
    var rows = await _db.query(
      'seats',
      where: 'ride_id = ?',
      whereArgs: <Object>[rideId],
      orderBy: 'created_at ASC',
    );
    if (rows.isNotEmpty) {
      return rows
          .map((row) => Map<String, Object?>.from(row))
          .toList(growable: false);
    }

    final baseFareMinor = _defaultSeatBaseFareMinor(ride);
    final nowIso = _nowUtc().toUtc().toIso8601String();
    final blueprints = <Map<String, Object?>>[
      <String, Object?>{
        'code': 'front_right',
        'type': 'front',
        'markup_percent': 10,
      },
      <String, Object?>{
        'code': 'back_left',
        'type': 'window',
        'markup_percent': 5,
      },
      <String, Object?>{
        'code': 'back_middle',
        'type': 'middle',
        'markup_percent': 0,
      },
      <String, Object?>{
        'code': 'back_right',
        'type': 'window',
        'markup_percent': 5,
      },
    ];
    for (final blueprint in blueprints) {
      final code = blueprint['code'] as String;
      final markupPercent = (blueprint['markup_percent'] as num).toInt();
      final markupMinor = (baseFareMinor * markupPercent / 100).round();
      await _db.insert('seats', <String, Object?>{
        'id': 'seat:$rideId:$code',
        'ride_id': rideId,
        'seat_code': code,
        'seat_type': blueprint['type'] as String,
        'base_fare_minor': baseFareMinor,
        'markup_minor': markupMinor,
        'passenger_user_id': null,
        'assignment_locked': 1,
        'created_at': nowIso,
        'updated_at': nowIso,
      }, conflictAlgorithm: ConflictAlgorithm.ignore);
    }

    rows = await _db.query(
      'seats',
      where: 'ride_id = ?',
      whereArgs: <Object>[rideId],
      orderBy: 'created_at ASC',
    );
    return rows
        .map((row) => Map<String, Object?>.from(row))
        .toList(growable: false);
  }

  int _defaultSeatBaseFareMinor(Map<String, Object?> ride) {
    final baseFareMinor = (ride['base_fare_minor'] as num?)?.toInt() ?? 0;
    if (baseFareMinor > 0) {
      return (baseFareMinor / 4).round();
    }
    final totalFareMinor = (ride['total_fare_minor'] as num?)?.toInt() ?? 0;
    if (totalFareMinor > 0) {
      return (totalFareMinor / 4).round();
    }
    return 7000;
  }

  int _dailyRateForRide(Map<String, Object?> ride, int fallbackMinor) {
    final daily = (ride['daily_rate_minor'] as num?)?.toInt() ?? 0;
    if (daily > 0) {
      return daily;
    }
    final totalFareMinor = (ride['total_fare_minor'] as num?)?.toInt() ?? 0;
    if (totalFareMinor > 0) {
      return totalFareMinor;
    }
    return fallbackMinor;
  }

  int _connectionFeeForRide(Map<String, Object?> ride) {
    final explicit = (ride['connection_fee_minor'] as num?)?.toInt() ?? 0;
    if (explicit > 0) {
      return explicit;
    }
    final scope = ((ride['trip_scope'] as String?) ?? '').trim().toLowerCase();
    if (scope == 'cross_country' || scope == 'international') {
      return 20000;
    }
    if (scope == 'inter_state') {
      return 10000;
    }
    return 5000;
  }

  bool _isConnectionFeePaid(Map<String, Object?> ride) {
    if (_asBool(ride['connection_fee_paid'])) {
      return true;
    }
    final paidAt = (ride['connection_fee_paid_at'] as String?)?.trim() ?? '';
    if (paidAt.isNotEmpty) {
      return true;
    }
    final status = ((ride['status'] as String?) ?? '').trim().toLowerCase();
    return status == 'connection_fee_paid';
  }

  bool _isTerminalRideStatus(String status) {
    return status == 'cancelled' ||
        status == 'completed' ||
        status == 'finance_settled';
  }

  bool _asBool(Object? value) {
    if (value is bool) {
      return value;
    }
    if (value is num) {
      return value.toInt() == 1;
    }
    if (value is String) {
      final normalized = value.trim().toLowerCase();
      return normalized == '1' || normalized == 'true';
    }
    return false;
  }

  int? _asInt(Object? value, {required int? fallback}) {
    if (value is int) {
      return value;
    }
    if (value is num) {
      return value.toInt();
    }
    if (value is String) {
      return int.tryParse(value.trim()) ?? fallback;
    }
    return fallback;
  }

  DateTime? _parseUtc(Object? raw) {
    final text = raw is String ? raw.trim() : '';
    if (text.isEmpty) {
      return null;
    }
    return DateTime.tryParse(text)?.toUtc();
  }

  List<String> _selectedSeatCodesFromBody(Object? rawSeatIds) {
    if (rawSeatIds is! List) {
      return const <String>[];
    }
    final codes = <String>{};
    for (final value in rawSeatIds) {
      final code = _seatCodeFromInput(value?.toString() ?? '');
      if (code != null) {
        codes.add(code);
      }
    }
    return codes.toList(growable: false);
  }

  String? _seatCodeFromInput(String raw) {
    final normalized = raw.trim().toLowerCase().replaceAll('-', '_');
    switch (normalized) {
      case 'front_right':
      case 'frontright':
        return 'front_right';
      case 'back_left':
      case 'backleft':
        return 'back_left';
      case 'back_middle':
      case 'backmiddle':
        return 'back_middle';
      case 'back_right':
      case 'backright':
        return 'back_right';
      default:
        return null;
    }
  }

  String _seatIdFromCode(String seatCode) {
    return seatCode.trim().toUpperCase();
  }

  void _requireAuthenticated(Request request) {
    if ((request.requestContext.userId ?? '').isEmpty) {
      throw const UnauthorizedActionError(code: 'unauthorized');
    }
  }

  void _requireRole(Request request, Set<String> allowedRoles) {
    final role = (request.requestContext.role ?? '').trim().toLowerCase();
    if (!allowedRoles.contains(role)) {
      throw const UnauthorizedActionError(code: 'forbidden');
    }
  }
}
