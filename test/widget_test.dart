import 'package:flutter_test/flutter_test.dart';
import 'package:hailo_core/main.dart';

void main() {
  testWidgets('App bootstrap smoke test', (WidgetTester tester) async {
    await tester.pumpWidget(const MyApp());
    expect(find.byType(MyApp), findsOneWidget);
  });
}
