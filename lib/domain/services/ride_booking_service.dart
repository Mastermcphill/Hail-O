import 'package:sqflite/sqflite.dart';

import '../../data/sqlite/dao/rides_dao.dart';
import '../models/ride_trip.dart';
import '../models/pricing_quote.dart';
import 'pricing_engine_service.dart';
import 'ride_booking_guard_service.dart';

class RideBookingService {
  RideBookingService(
    this.db, {
    RideBookingGuardService? guardService,
    PricingEngineService? pricingEngineService,
  }) : _guardService = guardService ?? RideBookingGuardService(db),
       _pricingEngineService =
           pricingEngineService ?? const PricingEngineService();

  final DatabaseExecutor db;
  final RideBookingGuardService _guardService;
  final PricingEngineService _pricingEngineService;

  Future<void> bookRide(RideTrip ride) async {
    final isCrossBorder =
        ride.tripScope == TripScope.crossCountry ||
        ride.tripScope == TripScope.international;
    await _guardService.assertCanBookRide(
      riderUserId: ride.riderId,
      isCrossBorder: isCrossBorder,
      tripScope: ride.tripScope,
    );
    await RidesDao(db).createRide(ride, viaRideBookingService: true);
  }

  Future<RideTrip> bookRideWithPricing({
    required RideTrip ride,
    required int distanceMeters,
    required int durationSeconds,
    required int luggageCount,
    required PricingVehicleClass vehicleClass,
    required DateTime requestedAtUtc,
    String? originCountry,
    String? destinationCountry,
  }) async {
    final quote = _pricingEngineService.quote(
      tripScope: ride.tripScope.dbValue,
      distanceMeters: distanceMeters,
      durationSeconds: durationSeconds,
      luggageCount: luggageCount,
      vehicleClass: vehicleClass,
      requestedAtUtc: requestedAtUtc,
    );
    final pricedRide = _withPricingQuote(ride, quote);
    final isCrossBorder =
        ride.tripScope == TripScope.crossCountry ||
        ride.tripScope == TripScope.international;
    await _guardService.assertCanBookRide(
      riderUserId: pricedRide.riderId,
      isCrossBorder: isCrossBorder,
      tripScope: pricedRide.tripScope,
      originCountry: originCountry,
      destinationCountry: destinationCountry,
    );
    await RidesDao(db).createRide(pricedRide, viaRideBookingService: true);
    return pricedRide;
  }

  Future<void> bookAwaitingConnectionFeeRide({
    required String rideId,
    required String riderId,
    required String driverId,
    required TripScope tripScope,
    required int feeMinor,
    required DateTime bidAcceptedAt,
    required DateTime feeDeadlineAt,
    required DateTime nowUtc,
  }) async {
    final isCrossBorder =
        tripScope == TripScope.crossCountry ||
        tripScope == TripScope.international;
    await _guardService.assertCanBookRide(
      riderUserId: riderId,
      isCrossBorder: isCrossBorder,
      tripScope: tripScope,
    );
    await RidesDao(db).upsertAwaitingConnectionFee(
      rideId: rideId,
      riderId: riderId,
      driverId: driverId,
      tripScope: tripScope.dbValue,
      feeMinor: feeMinor,
      bidAcceptedAtIso: bidAcceptedAt.toUtc().toIso8601String(),
      feeDeadlineAtIso: feeDeadlineAt.toUtc().toIso8601String(),
      nowIso: nowUtc.toUtc().toIso8601String(),
      viaRideBookingService: true,
    );
  }

  RideTrip _withPricingQuote(RideTrip ride, PricingQuote quote) {
    return RideTrip(
      id: ride.id,
      riderId: ride.riderId,
      driverId: ride.driverId,
      routeId: ride.routeId,
      pickupNodeId: ride.pickupNodeId,
      dropoffNodeId: ride.dropoffNodeId,
      tripScope: ride.tripScope,
      status: ride.status,
      biddingMode: ride.biddingMode,
      baseFareMinor: ride.baseFareMinor,
      premiumMarkupMinor: ride.premiumMarkupMinor,
      charterMode: ride.charterMode,
      dailyRateMinor: ride.dailyRateMinor,
      totalFareMinor: quote.fareMinor,
      connectionFeeMinor: ride.connectionFeeMinor,
      connectionFeePaid: ride.connectionFeePaid,
      pricingVersion: quote.ruleVersion,
      pricingBreakdownJson: quote.breakdownJson,
      quotedFareMinor: quote.fareMinor,
      bidAcceptedAt: ride.bidAcceptedAt,
      connectionFeeDeadlineAt: ride.connectionFeeDeadlineAt,
      connectionFeePaidAt: ride.connectionFeePaidAt,
      startedAt: ride.startedAt,
      arrivedAt: ride.arrivedAt,
      cancelledAt: ride.cancelledAt,
      createdAt: ride.createdAt,
      updatedAt: ride.updatedAt,
    );
  }
}
