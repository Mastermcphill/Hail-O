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
        idempotencyKey: 'idem_checkout_1',
      );

      expect(purchaseId, isNotEmpty);

      final timeline = await repository.fetchTimeline(purchaseId);
      expect(timeline, isNotEmpty);
      expect(
        timeline.map((event) => event.title),
        containsAll(<String>['Offer accepted', 'Seats locked']),
      );
    });

    test('keeps purchase id stable for the same idempotency key', () async {
      final offers = await repository.fetchOffers();
      final offerId = offers.first.id;
      final selection = SeatSelection(
        offerId: offerId,
        seatCount: 3,
        assignments: const <SeatAssignment>[
          SeatAssignment(seatNumber: 1, name: 'Ada', email: 'ada@test.dev'),
          SeatAssignment(seatNumber: 2, name: 'Kunle', email: 'kunle@test.dev'),
          SeatAssignment(seatNumber: 3, name: 'Tobi', email: 'tobi@test.dev'),
        ],
      );

      final first = await repository.createCheckout(
        selection,
        idempotencyKey: 'stable_idem_key',
      );
      final second = await repository.createCheckout(
        selection,
        idempotencyKey: 'stable_idem_key',
      );

      expect(first, isNotEmpty);
      expect(second, first);
    });

    test('updates seats and assignments and appends timeline events', () async {
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
        idempotencyKey: 'manage_seats_idem',
      );

      final updatedSeats = await repository.updateSeatCount(
        purchaseId: purchaseId,
        seatCount: 3,
      );
      expect(updatedSeats.seatCount, 3);

      final updatedAssignments = await repository.updateAssignments(
        purchaseId: purchaseId,
        assignments: const <SeatAssignment>[
          SeatAssignment(seatNumber: 1, name: 'Ada', email: 'ada@test.dev'),
          SeatAssignment(seatNumber: 2, name: 'Kunle', email: 'kunle@test.dev'),
          SeatAssignment(seatNumber: 3, name: 'Tobi', email: 'tobi@test.dev'),
        ],
      );
      expect(updatedAssignments.assignments.length, 3);

      final timeline = await repository.fetchTimeline(purchaseId);
      final titles = timeline.map((event) => event.title).toList();
      expect(titles, contains('SEATS_UPDATED'));
      expect(titles, contains('ASSIGNMENT_UPDATED'));
    });
  });
}
