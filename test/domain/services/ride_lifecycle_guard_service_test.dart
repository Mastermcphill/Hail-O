import 'package:flutter_test/flutter_test.dart';
import 'package:hail_o_finance_core/domain/services/ride_lifecycle_guard_service.dart';

void main() {
  final guard = RideLifecycleGuardService();

  test('cancellation allowed only from cancellable states', () {
    expect(() => guard.assertCanCancel('accepted'), returnsNormally);
    expect(() => guard.assertCanCancel('in_progress'), returnsNormally);

    expect(
      () => guard.assertCanCancel('completed'),
      throwsA(isA<RideLifecycleViolation>()),
    );
    expect(
      () => guard.assertCanCancel('finance_settled'),
      throwsA(isA<RideLifecycleViolation>()),
    );
  });

  test('connection fee payment only from awaiting_connection_fee', () {
    expect(
      () => guard.assertCanMarkConnectionFeePaid('awaiting_connection_fee'),
      returnsNormally,
    );
    expect(
      () => guard.assertCanMarkConnectionFeePaid('pending'),
      throwsA(isA<RideLifecycleViolation>()),
    );
    expect(
      () => guard.assertCanMarkConnectionFeePaid('cancelled'),
      throwsA(isA<RideLifecycleViolation>()),
    );
  });

  test('finance settlement blocks cancelled rides', () {
    expect(() => guard.assertCanSettleFinance('in_progress'), returnsNormally);
    expect(
      () => guard.assertCanSettleFinance('cancelled'),
      throwsA(isA<RideLifecycleViolation>()),
    );
  });
}
