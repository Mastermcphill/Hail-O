import 'package:shelf/shelf.dart';
import 'package:shelf_router/shelf_router.dart';

import '../../../lib/domain/models/user.dart';
import '../../../lib/domain/services/auth_service.dart';
import '../../infra/audit_logger.dart';
import '../../infra/request_context.dart';
import '../../infra/token_service.dart';
import '../../server/http_utils.dart';
import 'phone_auth_service.dart';

class AuthController {
  AuthController({
    AuthService? authService,
    required TokenService tokenService,
    PhoneAuthService? phoneAuthService,
    AuditLogger? auditLogger,
  }) : _authService = authService,
       _tokenService = tokenService,
       _phoneAuthService = phoneAuthService,
       _auditLogger = auditLogger ?? AuditLogger();

  final AuthService? _authService;
  final TokenService _tokenService;
  final PhoneAuthService? _phoneAuthService;
  final AuditLogger _auditLogger;

  Router get router {
    final router = Router();
    if (_authService != null) {
      router.post('/register', _register);
      router.post('/login', _login);
    }
    if (_phoneAuthService != null) {
      router.post('/otp/request', _requestOtp);
      router.post('/otp/verify', _verifyOtp);
      router.post('/token/refresh', _refreshToken);
    }
    return router;
  }

  Future<Response> _register(Request request) async {
    final authService = _authService;
    if (authService == null) {
      return jsonErrorResponse(
        request,
        404,
        code: 'route_not_found',
        message: 'Route not found',
      );
    }
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
    final referralCode = (body['referral_code'] as String?)?.trim();
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

    try {
      final result = await authService.register(
        email: email,
        password: password,
        role: role,
        idempotencyKey: idempotencyKey,
        displayName: displayName,
        nextOfKin: nextOfKin,
        referralCode: referralCode,
      );
      _auditLogger.authAttempt(
        traceId: request.requestContext.traceId,
        action: 'register',
        email: email,
        role: role.dbValue,
        success: true,
      );
      return jsonResponse(201, result);
    } catch (error) {
      _auditLogger.authAttempt(
        traceId: request.requestContext.traceId,
        action: 'register',
        email: email,
        role: role.dbValue,
        success: false,
        reasonCode: error.runtimeType.toString(),
      );
      rethrow;
    }
  }

  Future<Response> _login(Request request) async {
    final authService = _authService;
    if (authService == null) {
      return jsonErrorResponse(
        request,
        404,
        code: 'route_not_found',
        message: 'Route not found',
      );
    }
    final body = await readJsonBody(request);
    final email = (body['email'] as String?)?.trim() ?? '';
    final password = (body['password'] as String?) ?? '';
    try {
      final login = await authService.login(email: email, password: password);
      final token = _tokenService.issueToken(
        userId: (login['user_id'] as String?) ?? '',
        role: (login['role'] as String?) ?? UserRole.rider.dbValue,
      );
      _auditLogger.authAttempt(
        traceId: request.requestContext.traceId,
        action: 'login',
        email: email,
        role: (login['role'] as String?) ?? UserRole.rider.dbValue,
        success: true,
      );
      return jsonResponse(200, <String, Object?>{...login, 'token': token});
    } catch (error) {
      _auditLogger.authAttempt(
        traceId: request.requestContext.traceId,
        action: 'login',
        email: email,
        success: false,
        reasonCode: error.runtimeType.toString(),
      );
      rethrow;
    }
  }

  Future<Response> _requestOtp(Request request) async {
    final phoneAuthService = _phoneAuthService;
    if (phoneAuthService == null) {
      return jsonErrorResponse(
        request,
        404,
        code: 'route_not_found',
        message: 'Route not found',
      );
    }
    final body = await readJsonBody(request);
    final phoneE164 = (body['phone_e164'] as String?)?.trim() ?? '';
    try {
      final payload = await phoneAuthService.requestOtp(phoneE164: phoneE164);
      _auditLogger.authAttempt(
        traceId: request.requestContext.traceId,
        action: 'otp_request',
        email: phoneE164,
        success: true,
      );
      return jsonResponse(200, payload);
    } on PhoneAuthFailure catch (error) {
      _auditLogger.authAttempt(
        traceId: request.requestContext.traceId,
        action: 'otp_request',
        email: phoneE164,
        success: false,
        reasonCode: error.code,
      );
      return jsonErrorResponse(
        request,
        error.statusCode,
        code: error.code,
        message: error.message,
      );
    }
  }

  Future<Response> _verifyOtp(Request request) async {
    final phoneAuthService = _phoneAuthService;
    if (phoneAuthService == null) {
      return jsonErrorResponse(
        request,
        404,
        code: 'route_not_found',
        message: 'Route not found',
      );
    }
    final body = await readJsonBody(request);
    final phoneE164 = (body['phone_e164'] as String?)?.trim() ?? '';
    final code = (body['code'] as String?)?.trim() ?? '';
    try {
      final payload = await phoneAuthService.verifyOtp(
        phoneE164: phoneE164,
        code: code,
      );
      _auditLogger.authAttempt(
        traceId: request.requestContext.traceId,
        action: 'otp_verify',
        email: phoneE164,
        success: true,
      );
      return jsonResponse(200, payload);
    } on PhoneAuthFailure catch (error) {
      _auditLogger.authAttempt(
        traceId: request.requestContext.traceId,
        action: 'otp_verify',
        email: phoneE164,
        success: false,
        reasonCode: error.code,
      );
      return jsonErrorResponse(
        request,
        error.statusCode,
        code: error.code,
        message: error.message,
      );
    }
  }

  Future<Response> _refreshToken(Request request) async {
    final phoneAuthService = _phoneAuthService;
    if (phoneAuthService == null) {
      return jsonErrorResponse(
        request,
        404,
        code: 'route_not_found',
        message: 'Route not found',
      );
    }
    final body = await readJsonBody(request);
    final refreshToken = (body['refresh_token'] as String?)?.trim() ?? '';
    try {
      final payload = await phoneAuthService.refreshAccessToken(
        refreshToken: refreshToken,
      );
      return jsonResponse(200, payload);
    } on PhoneAuthFailure catch (error) {
      return jsonErrorResponse(
        request,
        error.statusCode,
        code: error.code,
        message: error.message,
      );
    }
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
