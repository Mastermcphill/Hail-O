import 'dart:convert';

import 'package:crypto/crypto.dart';

typedef AuditLogSink = void Function(String line);

class AuditLogger {
  AuditLogger({AuditLogSink? sink}) : _sink = sink ?? print;

  final AuditLogSink _sink;

  void authAttempt({
    required String traceId,
    required String action,
    required String email,
    required bool success,
    String? role,
    String? reasonCode,
  }) {
    _emit(<String, Object?>{
      'event': 'auth_attempt',
      'trace_id': traceId.trim(),
      'action': action.trim().toLowerCase(),
      'email_hash': _hashIdentifier(email),
      'role': role?.trim().toLowerCase(),
      'success': success,
      if (reasonCode != null && reasonCode.trim().isNotEmpty)
        'reason_code': reasonCode.trim().toLowerCase(),
    });
  }

  void adminAction({
    required String traceId,
    required String actorUserId,
    required String action,
    required bool success,
    String? targetId,
    String? reasonCode,
  }) {
    _emit(<String, Object?>{
      'event': 'admin_action',
      'trace_id': traceId.trim(),
      'actor_hash': _hashIdentifier(actorUserId),
      'action': action.trim().toLowerCase(),
      'success': success,
      if (targetId != null && targetId.trim().isNotEmpty)
        'target_hash': _hashIdentifier(targetId),
      if (reasonCode != null && reasonCode.trim().isNotEmpty)
        'reason_code': reasonCode.trim().toLowerCase(),
    });
  }

  void _emit(Map<String, Object?> payload) {
    final safePayload = <String, Object?>{
      ...payload,
      'timestamp_utc': DateTime.now().toUtc().toIso8601String(),
    };
    _sink(jsonEncode(safePayload));
  }

  String _hashIdentifier(String value) {
    final normalized = value.trim().toLowerCase();
    if (normalized.isEmpty) {
      return 'empty';
    }
    final digest = sha256.convert(utf8.encode(normalized)).toString();
    return digest.substring(0, 20);
  }
}
