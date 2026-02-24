import '../../../core/api/api_client.dart';
import '../../../core/api/api_errors.dart';
import '../../../core/api/api_paths.dart';

class AuthApi {
  AuthApi({required ApiClient apiClient}) : _apiClient = apiClient;

  final ApiClient _apiClient;

  Future<AuthSession> login({
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
    return AuthSession(token: token, role: role);
  }

  Future<void> register({
    required String email,
    required String password,
  }) async {
    await _apiClient.post(
      ApiPaths.authRegister,
      body: <String, dynamic>{
        'email': email.trim(),
        'password': password,
        'role': 'rider',
      },
    );
  }
}

class AuthSession {
  const AuthSession({required this.token, required this.role});

  final String token;
  final String role;

  bool get isAdmin => role == 'admin';
}

String normalizeAuthRole(String? role) {
  final normalized = (role ?? '').trim().toLowerCase();
  if (normalized == 'fleet') {
    return 'fleet_owner';
  }
  if (normalized.isEmpty) {
    return 'rider';
  }
  return normalized;
}

String mapLoginErrorMessage(Object error) {
  if (_isTimeoutError(error)) {
    return 'Server is taking too long to respond. Please try again.';
  }
  if (_isNetworkError(error)) {
    return 'No internet connection or server unreachable.';
  }
  if (_isUnauthorized(error)) {
    return 'Wrong email or password.';
  }
  return 'Login failed. Please try again.';
}

String mapRegisterErrorMessage(Object error) {
  if (_isTimeoutError(error)) {
    return 'Server is taking too long to respond. Please try again.';
  }
  if (_isNetworkError(error)) {
    return 'No internet connection or server unreachable.';
  }
  if (error is ApiException && error.statusCode == 409) {
    return 'An account with this email already exists.';
  }
  return 'Could not create account. Please try again.';
}

String _resolveRole(Map<String, dynamic> payload) {
  final directRole = _readString(payload['role']);
  if (directRole.isNotEmpty) {
    return normalizeAuthRole(directRole);
  }
  final claims = payload['claims'];
  if (claims is Map<String, dynamic>) {
    return normalizeAuthRole(_readString(claims['role']));
  }
  if (claims is Map<Object?, Object?>) {
    return normalizeAuthRole(_readString(claims['role']));
  }
  return 'rider';
}

String _readString(Object? value) {
  if (value is String) {
    return value.trim();
  }
  return '';
}

bool _isTimeoutError(Object error) {
  if (error is ApiException) {
    final code = (error.code ?? '').toLowerCase();
    if (code == 'request_timeout') {
      return true;
    }
    return error.message.toLowerCase().contains('timed out');
  }
  final message = error.toString().toLowerCase();
  return message.contains('timeout') || message.contains('timed out');
}

bool _isNetworkError(Object error) {
  if (error is ApiException) {
    final code = (error.code ?? '').toLowerCase();
    if (code == 'network_error' || code == 'client_error') {
      return true;
    }
  }
  final message = error.toString().toLowerCase();
  return message.contains('socketexception') ||
      message.contains('failed host lookup') ||
      message.contains('network');
}

bool _isUnauthorized(Object error) {
  return error is ApiException && error.statusCode == 401;
}
