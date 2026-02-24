import 'package:flutter_test/flutter_test.dart';
import 'package:hailo_core/core/observability/app_observability.dart';

void main() {
  group('AppObservability.scrubText', () {
    test('redacts emails', () {
      final value = AppObservability.scrubText('Contact rider@example.com now');
      expect(value, contains('[redacted-email]'));
      expect(value, isNot(contains('rider@example.com')));
    });

    test('redacts phone numbers', () {
      final value = AppObservability.scrubText('Call +1 (415) 555-0199 ASAP');
      expect(value, contains('[redacted-phone]'));
      expect(value, isNot(contains('555-0199')));
    });
  });
}
