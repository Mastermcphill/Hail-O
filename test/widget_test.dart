import 'package:flutter_test/flutter_test.dart';
import 'package:hailo_core/app.dart';

void main() {
  testWidgets('App bootstrap smoke test', (WidgetTester tester) async {
    await tester.pumpWidget(const HailoCoreApp(enableStartupWarmup: false));
    expect(find.byType(HailoCoreApp), findsOneWidget);
  });
}
