import 'package:flutter_test/flutter_test.dart';
import 'package:hailo_core/core/util/ids.dart';
import 'package:hailo_core/features/marketplace/models/outbox_item.dart';
import 'package:hailo_core/features/marketplace/models/purchase_snapshot.dart';
import 'package:hailo_core/features/marketplace/models/timeline_event.dart';
import 'package:hailo_core/features/marketplace/state/marketplace_controller.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'fake_marketplace_repository.dart';
import 'memory_marketplace_local_store.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() {
    SharedPreferences.setMockInitialValues(<String, Object>{});
  });

  String uniqueNamespace(String suffix) {
    return 'marketplace_test_${DateTime.now().microsecondsSinceEpoch}_$suffix';
  }

  test('outbox item persists across controller restart', () async {
    final namespace = uniqueNamespace('persist');
    final repo = FakeMarketplaceRepository()..createFailuresRemaining = 5;
    final store = MemoryMarketplaceLocalStore(namespace: namespace);
    final controller = MarketplaceController(
      repository: repo,
      localStore: store,
    );

    final pendingPurchaseId = await controller.submitSeats(
      offerId: 'starter_monthly',
      seatCount: 2,
      assignments: const <MarketplaceAssignment>[
        MarketplaceAssignment(seatIndex: 1, name: 'A', email: 'a@test.dev'),
      ],
    );
    expect(pendingPurchaseId.startsWith('pending-'), isTrue);

    final queued = await store.readAllOutboxItems();
    expect(queued.length, 1);

    controller.dispose();

    final storeAfterRestart = MemoryMarketplaceLocalStore(namespace: namespace);
    final persisted = await storeAfterRestart.readAllOutboxItems();
    expect(persisted.length, 1);
    await storeAfterRestart.close();
  });

  test('retry policy increments attempts and schedules next retry', () async {
    final namespace = uniqueNamespace('retry');
    final repo = FakeMarketplaceRepository()..updateSeatFailuresRemaining = 1;
    final store = MemoryMarketplaceLocalStore(namespace: namespace);
    final controller = MarketplaceController(
      repository: repo,
      localStore: store,
    );

    await controller.enqueueOutbox(
      MarketplaceOutboxItem(
        id: newRequestId(),
        type: MarketplaceOutboxType.updateSeats,
        purchaseId: 'purchase-retry',
        idempotencyKey: newIdempotencyKey(),
        payload: <String, dynamic>{'seatCount': 3},
        baseVersion: 1,
        status: MarketplaceOutboxStatus.queued,
        attempts: 0,
        createdAt: DateTime.now().toUtc(),
      ),
    );

    await controller.flushOutbox();

    final queued = await store.readAllOutboxItems();
    expect(queued.length, 1);
    final item = queued.first;
    expect(item.status, MarketplaceOutboxStatus.failed);
    expect(item.attempts, 1);
    expect(item.nextRetryAt, isNotNull);
    controller.dispose();
  });

  test(
    'version conflict rebases outbox item and next flush succeeds',
    () async {
      final namespace = uniqueNamespace('conflict');
      final repo = FakeMarketplaceRepository()..updateSeatConflictRemaining = 1;
      final store = MemoryMarketplaceLocalStore(namespace: namespace);
      final controller = MarketplaceController(
        repository: repo,
        localStore: store,
      );

      await controller.enqueueOutbox(
        MarketplaceOutboxItem(
          id: newRequestId(),
          type: MarketplaceOutboxType.updateSeats,
          purchaseId: 'purchase-conflict',
          idempotencyKey: newIdempotencyKey(),
          payload: <String, dynamic>{'seatCount': 4},
          baseVersion: 1,
          status: MarketplaceOutboxStatus.queued,
          attempts: 0,
          createdAt: DateTime.now().toUtc(),
        ),
      );

      await controller.flushOutbox();

      final afterConflict = await store.readAllOutboxItems();
      expect(afterConflict.length, 1);
      expect(afterConflict.first.baseVersion, 3);
      expect(afterConflict.first.status, MarketplaceOutboxStatus.queued);

      await controller.flushOutbox();

      final finalOutbox = await store.readAllOutboxItems();
      expect(finalOutbox, isEmpty);
      expect(repo.updateSeatCalls, greaterThanOrEqualTo(2));
      controller.dispose();
    },
  );

  test('timeline incremental merge avoids duplicates', () async {
    final namespace = uniqueNamespace('timeline');
    final repo = FakeMarketplaceRepository()
      ..initialTimeline = <MarketplaceTimelineEvent>[
        MarketplaceTimelineEvent(
          type: 'PURCHASE_CREATED',
          title: 'Purchase created',
          description: 'created',
          timestamp: DateTime.utc(2026, 2, 1, 10, 0, 0),
          status: 'ok',
          cursor: '1',
        ),
        MarketplaceTimelineEvent(
          type: 'SEATS_SELECTED',
          title: 'Seats selected',
          description: 'selected',
          timestamp: DateTime.utc(2026, 2, 1, 10, 1, 0),
          status: 'ok',
          cursor: '2',
        ),
      ]
      ..incrementalTimeline = <MarketplaceTimelineEvent>[
        MarketplaceTimelineEvent(
          type: 'SEATS_SELECTED',
          title: 'Seats selected',
          description: 'selected',
          timestamp: DateTime.utc(2026, 2, 1, 10, 1, 0),
          status: 'ok',
          cursor: '2',
        ),
        MarketplaceTimelineEvent(
          type: 'ASSIGNMENT_UPDATED',
          title: 'Assignment updated',
          description: 'updated',
          timestamp: DateTime.utc(2026, 2, 1, 10, 2, 0),
          status: 'ok',
          cursor: '3',
        ),
      ];
    final store = MemoryMarketplaceLocalStore(namespace: namespace);
    final controller = MarketplaceController(
      repository: repo,
      localStore: store,
    );

    await controller.refreshTimeline('purchase-1');
    await controller.refreshTimeline('purchase-1');

    expect(controller.timeline.length, 3);
    expect(
      controller.timeline.any((event) => event.type == 'ASSIGNMENT_UPDATED'),
      isTrue,
    );
    controller.dispose();
  });

  test('idempotency key is stable for same checkout input', () async {
    final namespace = uniqueNamespace('idem');
    final repo = FakeMarketplaceRepository()..createFailuresRemaining = 10;
    final store = MemoryMarketplaceLocalStore(namespace: namespace);
    final controller = MarketplaceController(
      repository: repo,
      localStore: store,
    );

    final first = await controller.submitSeats(
      offerId: 'starter_monthly',
      seatCount: 2,
      assignments: const <MarketplaceAssignment>[
        MarketplaceAssignment(seatIndex: 1, name: 'A', email: 'a@test.dev'),
      ],
    );
    final second = await controller.submitSeats(
      offerId: 'starter_monthly',
      seatCount: 2,
      assignments: const <MarketplaceAssignment>[
        MarketplaceAssignment(seatIndex: 1, name: 'A', email: 'a@test.dev'),
      ],
    );

    expect(first, second);
    controller.dispose();
  });
}
