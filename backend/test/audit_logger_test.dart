import 'dart:convert';

import 'package:test/test.dart';

import '../infra/audit_logger.dart';

void main() {
  test('authAttempt emits structured redacted log line', () {
    final lines = <String>[];
    final logger = AuditLogger(sink: lines.add);

    logger.authAttempt(
      traceId: 'trace-123',
      action: 'login',
      email: 'user@example.com',
      success: false,
      reasonCode: 'invalid_credentials',
    );

    expect(lines, hasLength(1));
    expect(lines.single, isNot(contains('user@example.com')));
    final payload = Map<String, Object?>.from(
      jsonDecode(lines.single) as Map<String, dynamic>,
    );
    expect(payload['event'], 'auth_attempt');
    expect(payload['trace_id'], 'trace-123');
    expect(payload['action'], 'login');
    expect(payload['success'], false);
    expect((payload['email_hash'] as String).length, 20);
    expect(payload.containsKey('timestamp_utc'), isTrue);
  });

  test('adminAction emits actor and target hashes only', () {
    final lines = <String>[];
    final logger = AuditLogger(sink: lines.add);

    logger.adminAction(
      traceId: 'trace-admin',
      actorUserId: 'admin-user-1',
      action: 'grant_credits',
      success: true,
      targetId: 'org-abc',
    );

    expect(lines, hasLength(1));
    expect(lines.single, isNot(contains('admin-user-1')));
    expect(lines.single, isNot(contains('org-abc')));
    final payload = Map<String, Object?>.from(
      jsonDecode(lines.single) as Map<String, dynamic>,
    );
    expect(payload['event'], 'admin_action');
    expect(payload['trace_id'], 'trace-admin');
    expect(payload['action'], 'grant_credits');
    expect(payload['success'], true);
    expect((payload['actor_hash'] as String).length, 20);
    expect((payload['target_hash'] as String).length, 20);
  });
}
