import 'package:flutter_test/flutter_test.dart';
import 'package:hailo_core/features/marketplace/data/marketplace_repository_mock.dart';
import 'package:hailo_core/features/marketplace/models/seat_selection.dart';

void main() {
  group('MarketplaceRepositoryMock', () {
    late MarketplaceRepositoryMock repository;

    setUp(() {
      repository = MarketplaceRepositoryMock();
    });

    test('returns seeded offers', () async {
      final offers = await repository.fetchOffers();

      expect(offers.length, inInclusiveRange(3, 5));
      expect(offers.first.id, isNotEmpty);
      expect(offers.first.priceMinor, greaterThan(0));
    });

    test('creates checkout and returns timeline events', () async {
      final offers = await repository.fetchOffers();
      final offerId = offers.first.id;

      final purchaseId = await repository.createCheckout(
        SeatSelection(
          offerId: offerId,
          seatCount: 2,
          assignments: const <SeatAssignment>[
            SeatAssignment(seatNumber: 1, name: 'Ada', email: 'ada@test.dev'),
            SeatAssignment(
              seatNumber: 2,
              name: 'Kunle',
              email: 'kunle@test.dev',
            ),
          ],
        ),
      );

      expect(purchaseId, isNotEmpty);

      final timeline = await repository.fetchTimeline(purchaseId);
      expect(timeline, isNotEmpty);
      expect(
        timeline.map((event) => event.title),
        containsAll(<String>['Offer accepted', 'Seats locked']),
      );
    });
  });
}
