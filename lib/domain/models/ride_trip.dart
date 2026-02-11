enum TripScope {
  intraCity('intra_city'),
  interState('inter_state'),
  crossCountry('cross_country'),
  international('international');

  const TripScope(this.dbValue);

  final String dbValue;

  static TripScope fromDbValue(String value) {
    return TripScope.values.firstWhere(
      (scope) => scope.dbValue == value,
      orElse: () => TripScope.intraCity,
    );
  }
}

class RideTrip {
  const RideTrip({
    required this.id,
    required this.riderId,
    required this.tripScope,
    required this.status,
    required this.baseFareMinor,
    required this.premiumMarkupMinor,
    required this.charterMode,
    required this.dailyRateMinor,
    required this.totalFareMinor,
    required this.connectionFeeMinor,
    required this.connectionFeePaid,
    required this.biddingMode,
    required this.createdAt,
    required this.updatedAt,
    this.pricingVersion = 'legacy_v0',
    this.pricingBreakdownJson = '{}',
    this.quotedFareMinor = 0,
    this.driverId,
    this.routeId,
    this.pickupNodeId,
    this.dropoffNodeId,
    this.bidAcceptedAt,
    this.connectionFeeDeadlineAt,
    this.connectionFeePaidAt,
    this.startedAt,
    this.arrivedAt,
    this.cancelledAt,
  });

  final String id;
  final String riderId;
  final String? driverId;
  final String? routeId;
  final String? pickupNodeId;
  final String? dropoffNodeId;
  final TripScope tripScope;
  final String status;
  final bool biddingMode;
  final int baseFareMinor;
  final int premiumMarkupMinor;
  final bool charterMode;
  final int dailyRateMinor;
  final int totalFareMinor;
  final int connectionFeeMinor;
  final bool connectionFeePaid;
  final String pricingVersion;
  final String pricingBreakdownJson;
  final int quotedFareMinor;
  final DateTime? bidAcceptedAt;
  final DateTime? connectionFeeDeadlineAt;
  final DateTime? connectionFeePaidAt;
  final DateTime? startedAt;
  final DateTime? arrivedAt;
  final DateTime? cancelledAt;
  final DateTime createdAt;
  final DateTime updatedAt;

  Map<String, Object?> toMap() {
    return <String, Object?>{
      'id': id,
      'rider_id': riderId,
      'driver_id': driverId,
      'route_id': routeId,
      'pickup_node_id': pickupNodeId,
      'dropoff_node_id': dropoffNodeId,
      'trip_scope': tripScope.dbValue,
      'status': status,
      'bidding_mode': biddingMode ? 1 : 0,
      'base_fare_minor': baseFareMinor,
      'premium_markup_minor': premiumMarkupMinor,
      'charter_mode': charterMode ? 1 : 0,
      'daily_rate_minor': dailyRateMinor,
      'total_fare_minor': totalFareMinor,
      'connection_fee_minor': connectionFeeMinor,
      'connection_fee_paid': connectionFeePaid ? 1 : 0,
      'pricing_version': pricingVersion,
      'pricing_breakdown_json': pricingBreakdownJson,
      'quoted_fare_minor': quotedFareMinor,
      'bid_accepted_at': bidAcceptedAt?.toUtc().toIso8601String(),
      'connection_fee_deadline_at': connectionFeeDeadlineAt
          ?.toUtc()
          .toIso8601String(),
      'connection_fee_paid_at': connectionFeePaidAt?.toUtc().toIso8601String(),
      'started_at': startedAt?.toUtc().toIso8601String(),
      'arrived_at': arrivedAt?.toUtc().toIso8601String(),
      'cancelled_at': cancelledAt?.toUtc().toIso8601String(),
      'created_at': createdAt.toUtc().toIso8601String(),
      'updated_at': updatedAt.toUtc().toIso8601String(),
    };
  }

  factory RideTrip.fromMap(Map<String, Object?> map) {
    DateTime? parseNullable(String key) {
      final value = map[key] as String?;
      return value == null ? null : DateTime.parse(value).toUtc();
    }

    return RideTrip(
      id: map['id'] as String,
      riderId: map['rider_id'] as String,
      driverId: map['driver_id'] as String?,
      routeId: map['route_id'] as String?,
      pickupNodeId: map['pickup_node_id'] as String?,
      dropoffNodeId: map['dropoff_node_id'] as String?,
      tripScope: TripScope.fromDbValue(map['trip_scope'] as String),
      status: map['status'] as String,
      biddingMode: ((map['bidding_mode'] as num?)?.toInt() ?? 0) == 1,
      baseFareMinor: (map['base_fare_minor'] as num?)?.toInt() ?? 0,
      premiumMarkupMinor: (map['premium_markup_minor'] as num?)?.toInt() ?? 0,
      charterMode: ((map['charter_mode'] as num?)?.toInt() ?? 0) == 1,
      dailyRateMinor: (map['daily_rate_minor'] as num?)?.toInt() ?? 0,
      totalFareMinor: (map['total_fare_minor'] as num?)?.toInt() ?? 0,
      connectionFeeMinor: (map['connection_fee_minor'] as num?)?.toInt() ?? 0,
      connectionFeePaid:
          ((map['connection_fee_paid'] as num?)?.toInt() ?? 0) == 1,
      pricingVersion: (map['pricing_version'] as String?) ?? 'legacy_v0',
      pricingBreakdownJson: (map['pricing_breakdown_json'] as String?) ?? '{}',
      quotedFareMinor: (map['quoted_fare_minor'] as num?)?.toInt() ?? 0,
      bidAcceptedAt: parseNullable('bid_accepted_at'),
      connectionFeeDeadlineAt: parseNullable('connection_fee_deadline_at'),
      connectionFeePaidAt: parseNullable('connection_fee_paid_at'),
      startedAt: parseNullable('started_at'),
      arrivedAt: parseNullable('arrived_at'),
      cancelledAt: parseNullable('cancelled_at'),
      createdAt: DateTime.parse(map['created_at'] as String).toUtc(),
      updatedAt: DateTime.parse(map['updated_at'] as String).toUtc(),
    );
  }
}
