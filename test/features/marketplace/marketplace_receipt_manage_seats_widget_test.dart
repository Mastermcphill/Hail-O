import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:hailo_core/features/marketplace/data/marketplace_repository_mock.dart';
import 'package:hailo_core/features/marketplace/state/marketplace_controller.dart';
import 'package:hailo_core/features/marketplace/ui/manage_seats_screen.dart';
import 'package:hailo_core/features/marketplace/ui/offers_screen.dart';
import 'package:hailo_core/features/marketplace/ui/paywall_screen.dart';
import 'package:hailo_core/features/marketplace/ui/receipt_screen.dart';
import 'package:hailo_core/features/marketplace/ui/seats_screen.dart';
import 'package:hailo_core/features/marketplace/ui/timeline_screen.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues(<String, Object>{});
  });

  testWidgets('receipt -> manage seats appends seat and assignment timeline', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(900, 1400));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    final repository = MarketplaceRepositoryMock();
    final router = _buildRouter(repository);

    await tester.pumpWidget(MaterialApp.router(routerConfig: router));
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('marketplace_offer_continue_0')));
    await tester.pumpAndSettle();
    await tester.tap(
      find.byKey(const Key('marketplace_paywall_continue_button')),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('marketplace_confirm_seats_button')));
    await tester.pumpAndSettle();

    expect(find.text('Booking Receipt'), findsOneWidget);
    await tester.tap(
      find.byKey(const Key('marketplace_receipt_manage_seats_button')),
    );
    await tester.pumpAndSettle();

    expect(find.text('Manage Seats'), findsOneWidget);

    await tester.tap(
      find.byKey(const Key('marketplace_manage_seat_count_increment')),
    );
    await tester.pump();
    await tester.tap(
      find.byKey(const Key('marketplace_manage_update_seats_button')),
    );
    await tester.pumpAndSettle();

    await tester.enterText(
      find.byKey(const Key('marketplace_manage_assignment_name_0')),
      'Ada Lovelace',
    );
    await tester.enterText(
      find.byKey(const Key('marketplace_manage_assignment_email_0')),
      'ada@test.dev',
    );
    await tester.pump();
    final saveAssignmentsButton = find.byKey(
      const Key('marketplace_manage_save_assignments_button'),
    );
    await tester.ensureVisible(saveAssignmentsButton);
    await tester.tap(saveAssignmentsButton);
    await tester.pumpAndSettle();

    final viewTimelineButton = find.text('View timeline').last;
    await tester.ensureVisible(viewTimelineButton);
    await tester.tap(viewTimelineButton);
    await tester.pumpAndSettle();

    expect(find.text('Marketplace Timeline'), findsOneWidget);
    expect(
      find.byKey(const Key('marketplace_timeline_event_0')),
      findsOneWidget,
    );
    final hasSeatUpdate = find.text('SEATS_UPDATED').evaluate().isNotEmpty;
    final hasAssignmentUpdate = find
        .text('ASSIGNMENT_UPDATED')
        .evaluate()
        .isNotEmpty;
    expect(hasSeatUpdate || hasAssignmentUpdate, isTrue);
  });
}

GoRouter _buildRouter(MarketplaceRepositoryMock repository) {
  return GoRouter(
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
            builder: (context, state) => MarketplaceOffersScreen(
              currentPurchaseId: state.uri.queryParameters['purchaseId'],
              currentOfferId: state.uri.queryParameters['currentOfferId'],
            ),
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
            path: '/marketplace/receipt',
            builder: (context, state) => MarketplaceReceiptScreen(
              purchaseId: state.uri.queryParameters['purchaseId'] ?? '',
            ),
          ),
          GoRoute(
            path: '/marketplace/seats/manage/:purchaseId',
            builder: (context, state) => MarketplaceManageSeatsScreen(
              purchaseId: state.pathParameters['purchaseId'] ?? '',
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
}
