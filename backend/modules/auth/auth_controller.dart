import 'package:shelf/shelf.dart';
import 'package:shelf_router/shelf_router.dart';

import '../../../lib/domain/models/user.dart';
import '../../../lib/domain/services/auth_service.dart';
import '../../infra/request_context.dart';
import '../../infra/token_service.dart';
import '../../server/http_utils.dart';

class AuthController {
  AuthController({
    required AuthService authService,
    required TokenService tokenService,
  }) : _authService = authService,
       _tokenService = tokenService;

  final AuthService _authService;
  final TokenService _tokenService;

  Router get router {
    final router = Router();
    router.post('/register', _register);
    router.post('/login', _login);
    return router;
  }

  Future<Response> _register(Request request) async {
    final body = await readJsonBody(request);
    final email = (body['email'] as String?)?.trim() ?? '';
    final password = (body['password'] as String?) ?? '';
    final requestedRole = (body['role'] as String?)?.trim().toLowerCase();
    late final UserRole role;
    if (requestedRole == UserRole.admin.dbValue) {
      final allowBootstrap = const bool.fromEnvironment(
        'HAILO_ALLOW_ADMIN_BOOTSTRAP',
        defaultValue: false,
      );
      if (!allowBootstrap) {
        return jsonErrorResponse(
          request,
          403,
          code: 'admin_registration_disabled',
          message: 'Admin self-registration is disabled.',
        );
      }
      role = UserRole.admin;
    } else {
      role = _parseRole(requestedRole ?? UserRole.rider.dbValue);
    }
    final displayName = (body['display_name'] as String?)?.trim();
    final idempotencyKey = request.requestContext.idempotencyKey ?? '';

    RegisterNextOfKinInput? nextOfKin;
    final nextOfKinRaw = body['next_of_kin'];
    if (nextOfKinRaw is Map<String, dynamic>) {
      nextOfKin = RegisterNextOfKinInput(
        fullName: (nextOfKinRaw['full_name'] as String?)?.trim() ?? '',
        phone: (nextOfKinRaw['phone'] as String?)?.trim() ?? '',
        relationship: (nextOfKinRaw['relationship'] as String?)?.trim(),
      );
    } else if (nextOfKinRaw is Map<Object?, Object?>) {
      nextOfKin = RegisterNextOfKinInput(
        fullName: (nextOfKinRaw['full_name'] as String?)?.trim() ?? '',
        phone: (nextOfKinRaw['phone'] as String?)?.trim() ?? '',
        relationship: (nextOfKinRaw['relationship'] as String?)?.trim(),
      );
    }

    final result = await _authService.register(
      email: email,
      password: password,
      role: role,
      idempotencyKey: idempotencyKey,
      displayName: displayName,
      nextOfKin: nextOfKin,
    );
    return jsonResponse(201, result);
  }

  Future<Response> _login(Request request) async {
    final body = await readJsonBody(request);
    final email = (body['email'] as String?)?.trim() ?? '';
    final password = (body['password'] as String?) ?? '';
    final login = await _authService.login(email: email, password: password);
    final token = _tokenService.issueToken(
      userId: (login['user_id'] as String?) ?? '',
      role: (login['role'] as String?) ?? UserRole.rider.dbValue,
    );
    return jsonResponse(200, <String, Object?>{...login, 'token': token});
  }

  UserRole _parseRole(String value) {
    final normalized = value.trim().toLowerCase();
    if (normalized == UserRole.driver.dbValue) {
      return UserRole.driver;
    }
    if (normalized == UserRole.admin.dbValue) {
      return UserRole.admin;
    }
    if (normalized == UserRole.fleetOwner.dbValue) {
      return UserRole.fleetOwner;
    }
    return UserRole.rider;
  }
}
