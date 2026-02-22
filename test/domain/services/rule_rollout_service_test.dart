import 'package:flutter_test/flutter_test.dart';
import 'package:hail_o_finance_core/domain/services/rule_rollout_service.dart';

void main() {
  const service = RuleRolloutService();

  test('0 and 100 percent rollout are deterministic edges', () {
    expect(
      service.isInRollout(subjectId: 'ride_1', percent: 0, salt: 'salt'),
      false,
    );
    expect(
      service.isInRollout(subjectId: 'ride_1', percent: 100, salt: 'salt'),
      true,
    );
  });

  test('bucket assignment is deterministic for same input', () {
    final first = service.bucketFor(subjectId: 'ride_abc', salt: 'salt_v1');
    final second = service.bucketFor(subjectId: 'ride_abc', salt: 'salt_v1');
    expect(first, second);
    expect(first, inInclusiveRange(0, 99));
  });
}
