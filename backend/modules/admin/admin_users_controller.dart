import 'package:shelf/shelf.dart';

import '../../../lib/domain/models/user.dart';
import '../../../lib/domain/services/auth_service.dart';
import '../../infra/request_context.dart';
import '../../server/http_utils.dart';

class AdminUsersController {
  AdminUsersController({required AuthService authService})
    : _authService = authService;

  final AuthService _authService;

  Future<Response> createUser(Request request) async {
    final role = (request.requestContext.role ?? '').trim().toLowerCase();
    if (role != UserRole.admin.dbValue) {
      return jsonErrorResponse(
        request,
        403,
        code: 'admin_required',
        message: 'Admin role required',
      );
    }

    final idempotencyKey = (request.requestContext.idempotencyKey ?? '').trim();
    if (idempotencyKey.isEmpty) {
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
