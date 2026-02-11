import 'package:flutter_test/flutter_test.dart';
import 'package:hail_o_finance_core/main.dart';

void main() {
  testWidgets('App bootstrap smoke test', (WidgetTester tester) async {
    await tester.pumpWidget(const MyApp());
    expect(find.text('Hail-O Backend Core Bootstrap'), findsOneWidget);
  });
}
