import 'package:shelf/shelf.dart';

import '../../../lib/domain/models/user.dart';
import '../../../lib/domain/services/auth_service.dart';
import '../../infra/audit_logger.dart';
import '../../infra/request_context.dart';
import '../../server/http_utils.dart';

class AdminUsersController {
  AdminUsersController({
    required AuthService authService,
    AuditLogger? auditLogger,
  }) : _authService = authService,
       _auditLogger = auditLogger ?? AuditLogger();

  final AuthService _authService;
  final AuditLogger _auditLogger;

  Future<Response> createUser(Request request) async {
    final role = (request.requestContext.role ?? '').trim().toLowerCase();
    if (role != UserRole.admin.dbValue) {
      _auditLogger.adminAction(
        traceId: request.requestContext.traceId,
        actorUserId: request.requestContext.userId ?? 'anonymous',
        action: 'create_user',
        success: false,
        reasonCode: 'admin_required',
      );
      return jsonErrorResponse(
        request,
        403,
        code: 'admin_required',
        message: 'Admin role required',
      );
    }

    final idempotencyKey = (request.requestContext.idempotencyKey ?? '').trim();
    if (idempotencyKey.isEmpty) {
      _auditLogger.adminAction(
        traceId: request.requestContext.traceId,
        actorUserId: request.requestContext.userId ?? 'anonymous',
        action: 'create_user',
        success: false,
        reasonCode: 'missing_idempotency_key',
      );
      return jsonErrorResponse(
        request,
        400,
        code: 'missing_idempotency_key',
        message: 'Idempotency-Key header is required',
      );
    }

    final body = await readJsonBody(request);
    final email = (body['email'] as String?)?.trim().toLowerCase() ?? '';
    final password = (body['password'] as String?) ?? '';
    final displayName = (body['display_name'] as String?)?.trim();
    final requestedRole = (body['role'] as String?)?.trim().toLowerCase() ?? '';
    final parsedRole = _parseRole(requestedRole);

    if (parsedRole == null) {
      _auditLogger.adminAction(
        traceId: request.requestContext.traceId,
        actorUserId: request.requestContext.userId ?? 'anonymous',
        action: 'create_user',
        success: false,
        reasonCode: 'unsupported_role',
      );
      return jsonErrorResponse(
        request,
        400,
        code: 'validation_error',
        message: 'Unsupported role',
      );
    }

    final result = await _authService.register(
      email: email,
      password: password,
      role: parsedRole,
      idempotencyKey: idempotencyKey,
      displayName: displayName,
    );
    _auditLogger.adminAction(
      traceId: request.requestContext.traceId,
      actorUserId: request.requestContext.userId ?? 'unknown',
      action: 'create_user',
      success: true,
      targetId: email,
    );
    return jsonResponse(201, result);
  }

  UserRole? _parseRole(String role) {
    if (role.isEmpty) {
      return null;
    }
    for (final value in UserRole.values) {
      if (value.dbValue == role) {
        return value;
      }
    }
    return null;
  }
}
