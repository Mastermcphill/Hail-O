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

class AuthLoginResult {
  const AuthLoginResult({required this.token, required this.role});

  final String token;
  final String role;

  bool get isAdmin => role == 'admin';
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
  if (error is ApiException && error.statusCode == 409) {
    return 'An account with this email already exists.';
  }
  return 'Could not create account. Please try again.';
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
  return 'rider';
}

String _readString(Object? value) {
  if (value is String) {
    return value.trim();
  }
  return '';
}
