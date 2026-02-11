import '../models/penalty_computation.dart';

enum RideType {
  intra('intra'),
  inter('inter'),
  international('international');

  const RideType(this.dbValue);
  final String dbValue;
}

class PenaltyEngineService {
  const PenaltyEngineService();

  PenaltyComputation computeCancellationPenaltyMinor({
    required RideType rideType,
    required int totalFareMinor,
    required DateTime scheduledDeparture,
    required DateTime cancelledAt,
  }) {
    final departure = scheduledDeparture.toUtc();
    final cancelled = cancelledAt.toUtc();
    final timeBeforeDepartureHours = departure.difference(cancelled).inHours;

    if (rideType == RideType.intra) {
      // Exact deterministic interpretation requested:
      // apply fixed N500 (50000 minor) only when cancellation is at/after departure.
      final isLate = !cancelled.isBefore(departure);
      return PenaltyComputation(
        penaltyMinor: isLate ? 50000 : 0,
        ruleCode: isLate
            ? 'intra_cancel_at_or_after_departure_fixed_500'
            : 'intra_cancel_before_departure_no_penalty',
        fixedFeeMinor: isLate ? 50000 : null,
        note: isLate
            ? 'Cancelled at or after scheduled departure.'
            : 'Cancelled before scheduled departure.',
      );
    }

    if (rideType == RideType.inter) {
      final percentApplied = timeBeforeDepartureHours > 10 ? 10 : 30;
      return PenaltyComputation(
        penaltyMinor: (totalFareMinor * percentApplied) ~/ 100,
        ruleCode: percentApplied == 10
            ? 'inter_cancel_gt_10h_10pct'
            : 'inter_cancel_lte_10h_30pct',
        percentApplied: percentApplied,
        note: 'Inter-state cancellation rule.',
      );
    }

    final percentApplied = timeBeforeDepartureHours < 24 ? 50 : 0;
    return PenaltyComputation(
      penaltyMinor: (totalFareMinor * percentApplied) ~/ 100,
      ruleCode: percentApplied == 50
          ? 'international_cancel_lt_24h_50pct'
          : 'international_cancel_gte_24h_0pct',
      percentApplied: percentApplied,
      note: 'International cancellation rule.',
    );
  }
}
