import '../../../core/api/api_client.dart';
import '../../../core/api/api_error.dart';
import '../../../core/api/api_errors.dart';
import '../../../core/api/api_paths.dart';
import '../../../core/routing/role_routes.dart';

class AuthApi {
  AuthApi({required ApiClient apiClient}) : _apiClient = apiClient;

  final ApiClient _apiClient;

  Future<AuthLoginResult> login({
    required String email,
    required String password,
  }) async {
    final response = await _apiClient.post(
      ApiPaths.authLogin,
      body: <String, dynamic>{'email': email.trim(), 'password': password},
    );
    final token = _readString(response['token']);
    if (token.isEmpty) {
      throw Exception('Login response missing token');
    }
    final role = _resolveRole(response);
    return AuthLoginResult(token: token, role: role);
  }

  Future<void> register({
    required String email,
    required String password,
    String role = 'rider',
    String? displayName,
  }) async {
    final normalizedDisplayName = (displayName ?? '').trim();
    await _apiClient.post(
      ApiPaths.authRegister,
      body: <String, dynamic>{
        'email': email.trim(),
        'password': password,
        'role': normalizeRole(role),
        if (normalizedDisplayName.isNotEmpty)
          'display_name': normalizedDisplayName,
      },
    );
  }

  Future<void> requestOtp({required String phoneE164}) async {
    await _apiClient.post(
      '/auth/otp/request',
      body: <String, dynamic>{'phone_e164': phoneE164.trim()},
    );
  }

  Future<OtpVerifyResult> verifyOtp({
    required String phoneE164,
    required String code,
  }) async {
    final response = await _apiClient.post(
      '/auth/otp/verify',
      body: <String, dynamic>{
        'phone_e164': phoneE164.trim(),
        'code': code.trim(),
      },
    );
    var accessToken = _readString(response['access_token']);
    if (accessToken.isEmpty) {
      accessToken = _readString(_readMap(response['data'])?['access_token']);
    }
    if (accessToken.isEmpty) {
      throw Exception('OTP verify response missing access_token');
    }
    var refreshToken = _readString(response['refresh_token']);
    if (refreshToken.isEmpty) {
      refreshToken = _readString(_readMap(response['data'])?['refresh_token']);
    }
    final userMap = _readMap(response['user']) ?? _readMap(response['data']);
    final role = normalizeRole(_readString(userMap?['role']));
    return OtpVerifyResult(
      accessToken: accessToken,
      refreshToken: refreshToken,
      role: role,
    );
  }

  Future<String> refreshAccessToken({required String refreshToken}) async {
    final response = await _apiClient.post(
      '/auth/token/refresh',
      body: <String, dynamic>{'refresh_token': refreshToken.trim()},
    );
    var accessToken = _readString(response['access_token']);
    if (accessToken.isEmpty) {
      accessToken = _readString(_readMap(response['data'])?['access_token']);
    }
    if (accessToken.isEmpty) {
      throw Exception('Refresh response missing access_token');
    }
    return accessToken;
  }
}

class AuthLoginResult {
  const AuthLoginResult({required this.token, required this.role});

  final String token;
  final String role;

  bool get isAdmin => role == 'admin';
}

class OtpVerifyResult {
  const OtpVerifyResult({
    required this.accessToken,
    required this.refreshToken,
    required this.role,
  });

  final String accessToken;
  final String refreshToken;
  final String role;
}

String mapLoginErrorMessage(Object error) {
  final envelope = ApiErrorEnvelope.fromException(error);
  if (envelope.kind == ApiErrorKind.timeout) {
    return 'Server is taking too long to respond. Please try again.';
  }
  if (envelope.kind == ApiErrorKind.network) {
    return 'No internet connection or server unreachable.';
  }
  if (envelope.kind == ApiErrorKind.unauthorized) {
    return 'Wrong email or password.';
  }
  if (envelope.kind == ApiErrorKind.server) {
    return 'Service is temporarily unavailable. Please try again in a moment.';
  }
  return 'Login failed. Please try again.';
}

String mapRegisterErrorMessage(Object error) {
  final envelope = ApiErrorEnvelope.fromException(error);
  if (envelope.kind == ApiErrorKind.timeout) {
    return 'Server is taking too long to respond. Please try again.';
  }
  if (envelope.kind == ApiErrorKind.network) {
    return 'No internet connection or server unreachable.';
  }
  if (envelope.kind == ApiErrorKind.server) {
    return 'Service is temporarily unavailable. Please try again in a moment.';
  }
  if (error is ApiException && error.statusCode == 409) {
    return 'An account with this email already exists.';
  }
  return 'Could not create account. Please try again.';
}

String mapOtpErrorMessage(Object error) {
  final envelope = ApiErrorEnvelope.fromException(error);
  if (envelope.kind == ApiErrorKind.timeout) {
    return 'Server is taking too long to respond. Please try again.';
  }
  if (envelope.kind == ApiErrorKind.network) {
    return 'No internet connection or server unreachable.';
  }
  if (envelope.kind == ApiErrorKind.unauthorized) {
    return 'OTP code is invalid or expired.';
  }
  if (envelope.kind == ApiErrorKind.forbidden) {
    return 'This account is disabled.';
  }
  if (error is ApiException && error.statusCode == 423) {
    return 'Too many attempts. Try again later.';
  }
  if (envelope.kind == ApiErrorKind.client) {
    return 'Please check your phone number and code.';
  }
  if (envelope.kind == ApiErrorKind.server) {
    return 'Service is temporarily unavailable. Please try again in a moment.';
  }
  return 'Authentication failed. Please try again.';
}

String _resolveRole(Map<String, dynamic> payload) {
  final directRole = _readString(payload['role']);
  if (directRole.isNotEmpty) {
    return normalizeRole(directRole);
  }
  final claims = payload['claims'];
  if (claims is Map<String, dynamic>) {
    return normalizeRole(_readString(claims['role']));
  }
  if (claims is Map<Object?, Object?>) {
    return normalizeRole(_readString(claims['role']));
  }
  final user = payload['user'];
  if (user is Map<String, dynamic>) {
    final role = _readString(user['role']);
    if (role.isNotEmpty) {
      return normalizeRole(role);
    }
  }
  if (user is Map<Object?, Object?>) {
    final role = _readString(user['role']);
    if (role.isNotEmpty) {
      return normalizeRole(role);
    }
  }
  return 'rider';
}

String _readString(Object? value) {
  if (value is String) {
    return value.trim();
  }
  return '';
}

Map<String, dynamic>? _readMap(Object? value) {
  if (value is Map<String, dynamic>) {
    return value;
  }
  if (value is Map) {
    return value.map(
      (key, nestedValue) =>
          MapEntry<String, dynamic>(key.toString(), nestedValue),
    );
  }
  return null;
}
