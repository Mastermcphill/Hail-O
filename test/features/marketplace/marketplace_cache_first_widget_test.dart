import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hailo_core/features/marketplace/models/offer.dart';
import 'package:hailo_core/features/marketplace/state/marketplace_controller.dart';
import 'package:hailo_core/features/marketplace/ui/offers_screen.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'fake_marketplace_repository.dart';
import 'memory_marketplace_local_store.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() {
    SharedPreferences.setMockInitialValues(<String, Object>{});
  });

  testWidgets('offers screen renders cached data when network is unavailable', (
    tester,
  ) async {
    final repo = FakeMarketplaceRepository()..throwOnOffers = true;
    final store = MemoryMarketplaceLocalStore(
      namespace: 'marketplace_widget_${DateTime.now().microsecondsSinceEpoch}',
    );
    await store.cacheOffers(const <MarketplaceOffer>[
      MarketplaceOffer(
        id: 'starter_monthly',
        title: 'Starter Monthly',
        subtitle: 'Cached subtitle',
        price: 1000,
        currency: 'NGN',
        interval: 'month',
        perks: <String>['Cached perk'],
      ),
    ], etag: 'cached-etag');
    final controller = MarketplaceController(
      repository: repo,
      localStore: store,
    );

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(body: MarketplaceOffersScreen(controller: controller)),
      ),
    );
    await tester.pump(const Duration(milliseconds: 300));
    await tester.pump(const Duration(milliseconds: 300));

    expect(find.text('Starter Monthly'), findsOneWidget);

    controller.stopSyncLoop();
    controller.dispose();
    await store.close();
    await tester.pumpWidget(const SizedBox.shrink());
  });
}
