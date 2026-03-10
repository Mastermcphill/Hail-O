import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hailo_core/features/auth/presentation/signup_screen.dart';

void main() {
  testWidgets('shows required field validation errors', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(const MaterialApp(home: SignupScreen()));

    final createAccountButton = find.widgetWithText(
      FilledButton,
      'Create passenger account',
    );
    await tester.ensureVisible(createAccountButton);
    await tester.tap(createAccountButton);
    await tester.pumpAndSettle();

    expect(find.text('Full name is required'), findsOneWidget);
    expect(find.text('Email is required'), findsOneWidget);
    expect(find.text('Password is required'), findsOneWidget);
    expect(find.text('Confirm your password'), findsOneWidget);
  });

  testWidgets('shows email, password length, and confirm mismatch errors', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(const MaterialApp(home: SignupScreen()));

    final fields = find.byType(TextFormField);
    await tester.enterText(fields.at(0), 'AB');
    await tester.enterText(fields.at(1), 'not-an-email');
    await tester.enterText(fields.at(2), '12345');
    await tester.enterText(fields.at(3), '1234');

    final createAccountButton = find.widgetWithText(
      FilledButton,
      'Create passenger account',
    );
    await tester.ensureVisible(createAccountButton);
    await tester.tap(createAccountButton);
    await tester.pumpAndSettle();

    expect(find.text('Enter a valid email address'), findsOneWidget);
    expect(find.text('Enter your full name'), findsOneWidget);
    expect(find.text('Password must be at least 8 characters'), findsOneWidget);
    expect(find.text('Passwords do not match'), findsOneWidget);
  });
}
