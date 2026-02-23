import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:hailo_core/features/marketplace/data/marketplace_repository_mock.dart';
import 'package:hailo_core/features/marketplace/state/marketplace_controller.dart';
import 'package:hailo_core/features/marketplace/ui/offers_screen.dart';
import 'package:hailo_core/features/marketplace/ui/paywall_screen.dart';
import 'package:hailo_core/features/marketplace/ui/seats_screen.dart';
import 'package:hailo_core/features/marketplace/ui/timeline_screen.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues(<String, Object>{});
  });

  testWidgets('failed checkout can resume via persisted idempotency key', (
    tester,
  ) async {
    final repository = MarketplaceRepositoryMock(
      failFirstCreateCheckout: true,
      delayFirstRestore: true,
    );

    final router = GoRouter(
      initialLocation: '/marketplace/offers',
      routes: <RouteBase>[
        ShellRoute(
          builder: (context, state, child) {
            return ChangeNotifierProvider<MarketplaceController>(
              create: (_) => MarketplaceController(repository: repository),
              child: Scaffold(body: child),
            );
          },
          routes: <RouteBase>[
            GoRoute(
              path: '/marketplace/offers',
              builder: (context, state) => const MarketplaceOffersScreen(),
            ),
            GoRoute(
              path: '/marketplace/paywall',
              builder: (context, state) => MarketplacePaywallScreen(
                offerId: state.uri.queryParameters['offerId'] ?? '',
              ),
            ),
            GoRoute(
              path: '/marketplace/seats',
              builder: (context, state) => MarketplaceSeatsScreen(
                offerId: state.uri.queryParameters['offerId'] ?? '',
              ),
            ),
            GoRoute(
              path: '/marketplace/timeline',
              builder: (context, state) => MarketplaceTimelineScreen(
                purchaseId: state.uri.queryParameters['purchaseId'] ?? '',
              ),
            ),
          ],
        ),
      ],
    );

    await tester.pumpWidget(MaterialApp.router(routerConfig: router));
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('marketplace_offer_continue_0')));
    await tester.pumpAndSettle();

    await tester.tap(
      find.byKey(const Key('marketplace_paywall_continue_button')),
    );
    await tester.pumpAndSettle();

    expect(find.text('Seat Selection'), findsOneWidget);

    await tester.tap(find.byKey(const Key('marketplace_confirm_seats_button')));
    await tester.pump();
    await tester.pumpAndSettle();

    expect(find.text('Seat Selection'), findsOneWidget);
    expect(
      find.byKey(const Key('marketplace_resume_purchase_button')),
      findsOneWidget,
    );

    await tester.tap(
      find.byKey(const Key('marketplace_resume_purchase_button')),
    );
    await tester.pump();
    await tester.pumpAndSettle();

    expect(find.text('Marketplace Timeline'), findsOneWidget);
    expect(
      find.byKey(const Key('marketplace_timeline_event_0')),
      findsOneWidget,
    );
  });
}
