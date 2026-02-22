import 'package:flutter_test/flutter_test.dart';
import 'package:hail_o_finance_core/domain/services/penalty_engine_service.dart';

void main() {
  group('PenaltyEngineService', () {
    test('compute penalty boundaries for intra/inter/international', () {
      const service = PenaltyEngineService();

      final scheduled = DateTime.utc(2026, 3, 2, 12);

      final intraEarly = service.computeCancellationPenaltyMinor(
        rideType: RideType.intra,
        totalFareMinor: 100000,
        scheduledDeparture: scheduled,
        cancelledAt: DateTime.utc(2026, 3, 2, 10, 59),
      );
      expect(intraEarly.penaltyMinor, 0);
      expect(intraEarly.ruleCode, 'intra_cancel_before_departure_no_penalty');
      expect(intraEarly.fixedFeeMinor, isNull);

      final intraLate = service.computeCancellationPenaltyMinor(
        rideType: RideType.intra,
        totalFareMinor: 100000,
        scheduledDeparture: scheduled,
        cancelledAt: DateTime.utc(2026, 3, 2, 12, 0),
      );
      expect(intraLate.penaltyMinor, 50000);
      expect(
        intraLate.ruleCode,
        'intra_cancel_at_or_after_departure_fixed_500',
      );
      expect(intraLate.fixedFeeMinor, 50000);

      final interGt10 = service.computeCancellationPenaltyMinor(
        rideType: RideType.inter,
        totalFareMinor: 100000,
        scheduledDeparture: scheduled,
        cancelledAt: DateTime.utc(2026, 3, 2, 1, 0),
      );
      expect(interGt10.penaltyMinor, 10000);
      expect(interGt10.ruleCode, 'inter_cancel_gt_10h_10pct');
      expect(interGt10.percentApplied, 10);

      final interEq10 = service.computeCancellationPenaltyMinor(
        rideType: RideType.inter,
        totalFareMinor: 100000,
        scheduledDeparture: scheduled,
        cancelledAt: DateTime.utc(2026, 3, 2, 2, 0),
      );
      expect(interEq10.penaltyMinor, 30000);
      expect(interEq10.ruleCode, 'inter_cancel_lte_10h_30pct');
      expect(interEq10.percentApplied, 30);

      final internationalEq24 = service.computeCancellationPenaltyMinor(
        rideType: RideType.international,
        totalFareMinor: 100000,
        scheduledDeparture: scheduled,
        cancelledAt: DateTime.utc(2026, 3, 1, 12, 0),
      );
      expect(internationalEq24.penaltyMinor, 0);
      expect(internationalEq24.ruleCode, 'international_cancel_gte_24h_0pct');
      expect(internationalEq24.percentApplied, 0);

      final internationalLt24 = service.computeCancellationPenaltyMinor(
        rideType: RideType.international,
        totalFareMinor: 100000,
        scheduledDeparture: DateTime.utc(2026, 3, 2, 12, 0),
        cancelledAt: DateTime.utc(2026, 3, 1, 13, 1),
      );
      expect(internationalLt24.penaltyMinor, 50000);
      expect(internationalLt24.ruleCode, 'international_cancel_lt_24h_50pct');
      expect(internationalLt24.percentApplied, 50);
    });
  });
}
