import 'package:shelf/shelf.dart';
import 'package:shelf_router/shelf_router.dart';

import '../../../lib/domain/models/user.dart';
import '../../../lib/domain/services/auth_service.dart';
import '../../infra/analytics_event_store.dart';
import '../../infra/audit_logger.dart';
import '../../infra/redis_client.dart';
import '../../infra/request_context.dart';
import '../../infra/token_service.dart';
import '../../server/http_utils.dart';
import 'phone_auth_service.dart';

class _OtpRateLimitBucket {
  _OtpRateLimitBucket({required this.windowStartUtc, required this.count});

  DateTime windowStartUtc;
  int count;
}

class _OtpRateLimiter {
  _OtpRateLimiter({
    required this.window,
    required this.requestLimitPerIp,
    required this.requestLimitPerPhone,
    required this.verifyLimitPerIp,
    required this.verifyLimitPerPhone,
    this.redisClient,
    DateTime Function()? nowUtc,
  }) : _nowUtc = nowUtc ?? (() => DateTime.now().toUtc());

  final Duration window;
  final int requestLimitPerIp;
  final int requestLimitPerPhone;
  final int verifyLimitPerIp;
  final int verifyLimitPerPhone;
  final RedisQueueClient? redisClient;
  final DateTime Function() _nowUtc;

  final Map<String, _OtpRateLimitBucket> _requestIpBuckets =
      <String, _OtpRateLimitBucket>{};
  final Map<String, _OtpRateLimitBucket> _requestPhoneBuckets =
      <String, _OtpRateLimitBucket>{};
  final Map<String, _OtpRateLimitBucket> _verifyIpBuckets =
      <String, _OtpRateLimitBucket>{};
  final Map<String, _OtpRateLimitBucket> _verifyPhoneBuckets =
      <String, _OtpRateLimitBucket>{};

  Future<bool> allowOtpRequest({
    required String clientIp,
    required String phoneE164,
  }) async {
    final now = _nowUtc();
    final ipKey = clientIp.trim().isEmpty ? 'unknown' : clientIp.trim();
    final phoneKey = _normalizePhoneKey(phoneE164);
    final ipAllowed = await _consumeRedis(
      key: 'ratelimit:otp:request:ip:$ipKey',
      limit: requestLimitPerIp,
    );
    if (ipAllowed == false ||
        (ipAllowed == null &&
            !_consume(_requestIpBuckets, ipKey, now, requestLimitPerIp))) {
      return false;
    }
    final phoneAllowed = await _consumeRedis(
      key: 'ratelimit:otp:request:phone:$phoneKey',
      limit: requestLimitPerPhone,
    );
    if (phoneAllowed == false ||
        (phoneAllowed == null &&
            !_consume(
              _requestPhoneBuckets,
              phoneKey,
              now,
              requestLimitPerPhone,
            ))) {
      return false;
    }
    return true;
  }

  Future<bool> allowOtpVerify({
    required String clientIp,
    required String phoneE164,
  }) async {
    final now = _nowUtc();
    final ipKey = clientIp.trim().isEmpty ? 'unknown' : clientIp.trim();
    final phoneKey = _normalizePhoneKey(phoneE164);
    final ipAllowed = await _consumeRedis(
      key: 'ratelimit:otp:verify:ip:$ipKey',
      limit: verifyLimitPerIp,
    );
    if (ipAllowed == false ||
        (ipAllowed == null &&
            !_consume(_verifyIpBuckets, ipKey, now, verifyLimitPerIp))) {
      return false;
    }
    final phoneAllowed = await _consumeRedis(
      key: 'ratelimit:otp:verify:phone:$phoneKey',
      limit: verifyLimitPerPhone,
    );
    if (phoneAllowed == false ||
        (phoneAllowed == null &&
            !_consume(
              _verifyPhoneBuckets,
              phoneKey,
              now,
              verifyLimitPerPhone,
            ))) {
      return false;
    }
    return true;
  }

  bool _consume(
    Map<String, _OtpRateLimitBucket> buckets,
    String key,
    DateTime now,
    int limit,
  ) {
    if (limit <= 0) {
      return true;
    }
    final bucket = buckets.putIfAbsent(
      key,
      () => _OtpRateLimitBucket(windowStartUtc: now, count: 0),
    );
    if (now.difference(bucket.windowStartUtc) >= window) {
      bucket.windowStartUtc = now;
      bucket.count = 0;
    }
    if (bucket.count >= limit) {
      return false;
    }
    bucket.count += 1;
    return true;
  }

  String _normalizePhoneKey(String value) {
    final normalized = value.trim();
    if (normalized.isEmpty) {
      return 'empty';
    }
    return normalized;
  }

  Future<bool?> _consumeRedis({required String key, required int limit}) async {
    final client = redisClient;
    if (client == null || limit <= 0) {
      return null;
    }
    try {
      final count = await client.incrementWithWindow(key, window: window);
      return count <= limit;
    } catch (_) {
      return null;
    }
  }
}

class AuthController {
  AuthController({
    AuthService? authService,
    required TokenService tokenService,
    PhoneAuthService? phoneAuthService,
    AuditLogger? auditLogger,
    AnalyticsEventStore? analyticsEventStore,
    Duration otpRateLimitWindow = const Duration(minutes: 10),
    int otpRequestLimitPerIp = 6,
    int otpRequestLimitPerPhone = 4,
    int otpVerifyLimitPerIp = 12,
    int otpVerifyLimitPerPhone = 8,
    RedisQueueClient? redisClient,
    DateTime Function()? nowUtc,
  }) : _authService = authService,
       _tokenService = tokenService,
       _phoneAuthService = phoneAuthService,
       _auditLogger = auditLogger ?? AuditLogger(),
       _analyticsEventStore = analyticsEventStore,
       _otpRateLimiter = phoneAuthService == null
           ? null
           : _OtpRateLimiter(
               window: otpRateLimitWindow,
               requestLimitPerIp: otpRequestLimitPerIp,
               requestLimitPerPhone: otpRequestLimitPerPhone,
               verifyLimitPerIp: otpVerifyLimitPerIp,
               verifyLimitPerPhone: otpVerifyLimitPerPhone,
               redisClient: redisClient,
               nowUtc: nowUtc,
             );

  final AuthService? _authService;
  final TokenService _tokenService;
  final PhoneAuthService? _phoneAuthService;
  final AuditLogger _auditLogger;
  final AnalyticsEventStore? _analyticsEventStore;
  final _OtpRateLimiter? _otpRateLimiter;

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
    final limiter = _otpRateLimiter;
    if (limiter != null &&
        !await limiter.allowOtpRequest(
          clientIp: _extractClientIp(request),
          phoneE164: phoneE164,
        )) {
      _auditLogger.authAttempt(
        traceId: request.requestContext.traceId,
        action: 'otp_request',
        email: phoneE164,
        success: false,
        reasonCode: 'rate_limited',
      );
      return jsonErrorResponse(
        request,
        429,
        code: 'rate_limited',
        message: 'Too many OTP requests. Try again later.',
      );
    }
    try {
      final payload = await phoneAuthService.requestOtp(phoneE164: phoneE164);
      _auditLogger.authAttempt(
        traceId: request.requestContext.traceId,
        action: 'otp_request',
        email: phoneE164,
        success: true,
      );
      await _analyticsEventStore?.emitFromRequest(
        request,
        name: 'auth.otp_requested',
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
    final limiter = _otpRateLimiter;
    if (limiter != null &&
        !await limiter.allowOtpVerify(
          clientIp: _extractClientIp(request),
          phoneE164: phoneE164,
        )) {
      _auditLogger.authAttempt(
        traceId: request.requestContext.traceId,
        action: 'otp_verify',
        email: phoneE164,
        success: false,
        reasonCode: 'rate_limited',
      );
      return jsonErrorResponse(
        request,
        429,
        code: 'rate_limited',
        message: 'Too many OTP verification attempts. Try again later.',
      );
    }
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
      await _analyticsEventStore?.emitFromRequest(
        request,
        name: 'auth.otp_verified',
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

  String _extractClientIp(Request request) {
    final forwarded = (request.headers['x-forwarded-for'] ?? '').trim();
    if (forwarded.isNotEmpty) {
      return forwarded.split(',').first.trim();
    }
    final realIp = (request.headers['x-real-ip'] ?? '').trim();
    if (realIp.isNotEmpty) {
      return realIp;
    }
    return 'unknown';
  }
}
