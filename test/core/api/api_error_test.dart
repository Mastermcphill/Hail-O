import 'package:flutter_test/flutter_test.dart';
import 'package:hailo_core/core/api/api_error.dart';
import 'package:hailo_core/core/api/api_errors.dart';

void main() {
  group('ApiErrorEnvelope', () {
    test('maps request timeout ApiException', () {
      final envelope = ApiErrorEnvelope.fromException(
        ApiException(
          statusCode: 0,
          code: 'request_timeout',
          message: 'Request timed out.',
        ),
      );

      expect(envelope.kind, ApiErrorKind.timeout);
      expect(
        envelope.friendlyMessage,
        'Server is taking too long to respond. Please try again.',
      );
    });

    test('maps unauthorized status', () {
      final envelope = ApiErrorEnvelope.fromException(
        ApiException(statusCode: 401, code: 'unauthorized', message: 'Denied'),
      );

      expect(envelope.kind, ApiErrorKind.unauthorized);
      expect(
        envelope.friendlyMessage,
        'Authentication failed. Please sign in again.',
      );
    });

    test('maps unknown errors safely', () {
      final envelope = ApiErrorEnvelope.fromException(Exception('boom'));

      expect(envelope.kind, ApiErrorKind.unknown);
      expect(
        envelope.friendlyMessage,
        'Something went wrong. Please try again.',
      );
    });

    test('maps circuit breaker temporary unavailability', () {
      final envelope = ApiErrorEnvelope.fromException(
        ApiException(
          statusCode: 503,
          code: 'service_temporarily_unavailable',
          message: 'Service temporarily unavailable.',
        ),
      );

      expect(envelope.kind, ApiErrorKind.server);
      expect(
        envelope.friendlyMessage,
        'Service is temporarily unavailable. Please try again in a moment.',
      );
    });
  });
}
