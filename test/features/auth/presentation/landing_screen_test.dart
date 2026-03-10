import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:hailo_core/features/auth/presentation/landing_screen.dart';

void main() {
  testWidgets('sign in button routes to login', (WidgetTester tester) async {
    final router = _routerForTest();
    await tester.pumpWidget(MaterialApp.router(routerConfig: router));

    final signInButton = find.widgetWithText(OutlinedButton, 'Sign in').first;
    await tester.ensureVisible(signInButton);
    await tester.tap(signInButton);
    await tester.pumpAndSettle();

    expect(find.text('Login target'), findsOneWidget);
  });

  testWidgets('get started button routes to signup', (
    WidgetTester tester,
  ) async {
    final router = _routerForTest();
    await tester.pumpWidget(MaterialApp.router(routerConfig: router));

    final getStartedButton = find
        .widgetWithText(FilledButton, 'Get started')
        .first;
    await tester.ensureVisible(getStartedButton);
    await tester.tap(getStartedButton);
    await tester.pumpAndSettle();

    expect(find.text('Signup target'), findsOneWidget);
  });

  testWidgets('driver CTA routes to driver application', (
    WidgetTester tester,
  ) async {
    final router = _routerForTest();
    await tester.pumpWidget(MaterialApp.router(routerConfig: router));

    final driverButton = find
        .widgetWithText(OutlinedButton, 'Become a driver')
        .first;
    tester.widget<OutlinedButton>(driverButton).onPressed!.call();
    await tester.pumpAndSettle();

    expect(find.text('Driver signup target'), findsOneWidget);
  });

  testWidgets('fleet CTA routes to fleet registration', (
    WidgetTester tester,
  ) async {
    final router = _routerForTest();
    await tester.pumpWidget(MaterialApp.router(routerConfig: router));

    final fleetButton = find
        .widgetWithText(OutlinedButton, 'Register fleet')
        .first;
    tester.widget<OutlinedButton>(fleetButton).onPressed!.call();
    await tester.pumpAndSettle();

    expect(find.text('Fleet signup target'), findsOneWidget);
  });

  testWidgets('admin is not visible on landing', (WidgetTester tester) async {
    final router = _routerForTest();
    await tester.pumpWidget(MaterialApp.router(routerConfig: router));

    expect(find.textContaining('Admin', findRichText: true), findsNothing);
  });
}

GoRouter _routerForTest() {
  return GoRouter(
    initialLocation: '/',
    routes: <RouteBase>[
      GoRoute(path: '/', builder: (context, state) => const LandingScreen()),
      GoRoute(
        path: '/login',
        builder: (context, state) =>
            const Scaffold(body: Center(child: Text('Login target'))),
      ),
      GoRoute(
        path: '/signup',
        builder: (context, state) =>
            const Scaffold(body: Center(child: Text('Signup target'))),
      ),
      GoRoute(
        path: '/apply/driver',
        builder: (context, state) =>
            const Scaffold(body: Center(child: Text('Driver signup target'))),
      ),
      GoRoute(
        path: '/apply/fleet',
        builder: (context, state) =>
            const Scaffold(body: Center(child: Text('Fleet signup target'))),
      ),
    ],
  );
}
