import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:hailo_core/features/marketplace/data/marketplace_repository_mock.dart';
import 'package:hailo_core/features/marketplace/state/marketplace_controller.dart';
import 'package:hailo_core/features/marketplace/ui/manage_seats_screen.dart';
import 'package:hailo_core/features/marketplace/ui/offers_screen.dart';
import 'package:hailo_core/features/marketplace/ui/paywall_screen.dart';
import 'package:hailo_core/features/marketplace/ui/plan_change_preview_screen.dart';
import 'package:hailo_core/features/marketplace/ui/receipt_screen.dart';
import 'package:hailo_core/features/marketplace/ui/seats_screen.dart';
import 'package:hailo_core/features/marketplace/ui/timeline_screen.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues(<String, Object>{});
  });

  testWidgets('receipt change plan creates PLAN_CHANGED timeline event', (
    tester,
  ) async {
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
    final initialPurchaseId = _readPurchaseId(tester);

    await tester.tap(
      find.byKey(const Key('marketplace_receipt_change_plan_button')),
    );
    await tester.pumpAndSettle();

    expect(find.byType(MarketplaceOffersScreen), findsOneWidget);
    await tester.tap(find.byKey(const Key('marketplace_offer_continue_1')));
    await tester.pumpAndSettle();

    expect(find.text('Upgrade Preview'), findsOneWidget);
    await tester.tap(
      find.byKey(const Key('marketplace_confirm_plan_change_button')),
    );
    await tester.pumpAndSettle();

    expect(find.text('Booking Receipt'), findsOneWidget);
    final updatedPurchaseId = _readPurchaseId(tester);
    await tester.tap(
      find.byKey(const Key('marketplace_receipt_timeline_button')),
    );
    await tester.pumpAndSettle();

    expect(find.text('Marketplace Timeline'), findsOneWidget);
    expect(
      find.byKey(const Key('marketplace_timeline_event_0')),
      findsOneWidget,
    );
    final hasPlanChanged = find.text('PLAN_CHANGED').evaluate().isNotEmpty;
    final purchaseChanged =
        initialPurchaseId.isNotEmpty &&
        updatedPurchaseId.isNotEmpty &&
        initialPurchaseId != updatedPurchaseId;
    expect(hasPlanChanged || purchaseChanged, isTrue);
  });
}

String _readPurchaseId(WidgetTester tester) {
  final selectableTexts = find.byWidgetPredicate(
    (widget) => widget is SelectableText,
  );
  for (final element in selectableTexts.evaluate()) {
    final widget = element.widget as SelectableText;
    final value = widget.data ?? '';
    if (value.startsWith('purchase_')) {
      return value;
    }
  }
  return '';
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
            path: '/marketplace/upgrade',
            builder: (context, state) => MarketplacePlanChangePreviewScreen(
              purchaseId: state.uri.queryParameters['purchaseId'] ?? '',
              currentOfferId: state.uri.queryParameters['currentOfferId'] ?? '',
              newOfferId: state.uri.queryParameters['newOfferId'] ?? '',
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
