import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:hailo_core/core/api/api_client.dart';
import 'package:hailo_core/core/storage/token_storage.dart';
import 'package:hailo_core/features/rider/offers_screen.dart';
import 'package:hailo_core/features/rider/paywall_screen.dart';
import 'package:hailo_core/features/rider/seat_selection_screen.dart';
import 'package:hailo_core/features/rider/timeline_screen.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('offers -> paywall -> seats -> timeline flow works', (
    tester,
  ) async {
    final apiClient = ApiClient(tokenStorage: const TokenStorage());
    addTearDown(apiClient.close);

    final router = GoRouter(
      initialLocation: '/rider/offers/ride_test_1?luggage=1&charter=0',
      routes: <RouteBase>[
        GoRoute(
          path: '/rider/offers/:rideId',
          builder: (context, state) => OffersScreen(
            apiClient: apiClient,
            rideId: state.pathParameters['rideId'] ?? '',
            luggageCount:
                int.tryParse(state.uri.queryParameters['luggage'] ?? '0') ?? 0,
            charterMode: state.uri.queryParameters['charter'] == '1',
          ),
        ),
        GoRoute(
          path: '/rider/paywall/:rideId',
          builder: (context, state) => PaywallScreen(
            apiClient: apiClient,
            rideId: state.pathParameters['rideId'] ?? '',
            offerPriceMinor:
                int.tryParse(state.uri.queryParameters['offerPrice'] ?? '0') ??
                0,
            charterMode: state.uri.queryParameters['charter'] == '1',
            luggageCount:
                int.tryParse(state.uri.queryParameters['luggage'] ?? '0') ?? 0,
          ),
        ),
        GoRoute(
          path: '/rider/seats/:rideId',
          builder: (context, state) => SeatSelectionScreen(
            apiClient: apiClient,
            rideId: state.pathParameters['rideId'] ?? '',
            offerPriceMinor:
                int.tryParse(state.uri.queryParameters['offerPrice'] ?? '0') ??
                0,
            charterMode: state.uri.queryParameters['charter'] == '1',
          ),
        ),
        GoRoute(
          path: '/rider/timeline/:purchaseId',
          builder: (context, state) => TimelineScreen(
            apiClient: apiClient,
            purchaseId: state.pathParameters['purchaseId'] ?? '',
            rideId: state.uri.queryParameters['rideId'],
          ),
        ),
      ],
    );

    await tester.pumpWidget(
      MaterialApp.router(
        routerConfig: router,
        theme: ThemeData(useMaterial3: true),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Blind Offers'), findsOneWidget);

    await tester.tap(find.byKey(const Key('offer_card_0')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));

    expect(find.text('Connection Fee Paywall'), findsOneWidget);

    await tester.binding.handlePopRoute();
    await tester.pump(const Duration(milliseconds: 500));
    expect(find.text('Blind Offers'), findsOneWidget);

    await tester.tap(find.byKey(const Key('offer_card_0')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));
    expect(find.text('Connection Fee Paywall'), findsOneWidget);

    await tester.tap(find.byKey(const Key('paywall_continue_button')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 1000));

    expect(find.text('Seat Selection'), findsOneWidget);

    await tester.binding.handlePopRoute();
    await tester.pump(const Duration(milliseconds: 500));
    expect(find.text('Connection Fee Paywall'), findsOneWidget);

    await tester.tap(find.byKey(const Key('paywall_continue_button')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 1000));
    expect(find.text('Seat Selection'), findsOneWidget);

    await tester.enterText(find.byKey(const Key('seat_count_field')), '3');
    await tester.pump();

    final confirmButton = find.byKey(const Key('confirm_seats_button'));
    expect(confirmButton, findsOneWidget);
    await tester.tap(confirmButton);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));

    expect(find.text('Purchase Timeline'), findsOneWidget);
    expect(find.byKey(const Key('timeline_widget')), findsOneWidget);
    expect(find.byKey(const Key('timeline_step_REQUESTED')), findsOneWidget);
  });
}
