import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:hailo_core/features/auth/presentation/landing_screen.dart';

void main() {
  testWidgets('sign in button routes to login', (WidgetTester tester) async {
    final router = _routerForTest();
    await tester.pumpWidget(MaterialApp.router(routerConfig: router));

    await tester.tap(find.widgetWithText(OutlinedButton, 'Sign in'));
    await tester.pumpAndSettle();

    expect(find.text('Login target'), findsOneWidget);
  });

  testWidgets('get started button routes to signup', (
    WidgetTester tester,
  ) async {
    final router = _routerForTest();
    await tester.pumpWidget(MaterialApp.router(routerConfig: router));

    await tester.tap(find.widgetWithText(FilledButton, 'Get Started'));
    await tester.pumpAndSettle();

    expect(find.text('Signup target'), findsOneWidget);
  });

  testWidgets('admin login button routes to admin login', (
    WidgetTester tester,
  ) async {
    final router = _routerForTest();
    await tester.pumpWidget(MaterialApp.router(routerConfig: router));

    await tester.tap(find.widgetWithText(TextButton, 'Admin login'));
    await tester.pumpAndSettle();

    expect(find.text('Admin login target'), findsOneWidget);
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
        path: '/admin-login',
        builder: (context, state) =>
            const Scaffold(body: Center(child: Text('Admin login target'))),
      ),
    ],
  );
}
