import 'package:flutter/foundation.dart';

import '../../../core/api/api_client.dart';
import '../../../core/routing/role_routes.dart';
import '../../../core/storage/token_storage.dart';
import '../data/auth_api.dart';

enum AuthStatus { loading, anonymous, authenticated }

class AuthSession extends ChangeNotifier {
  AuthSession({
    required TokenStorage tokenStorage,
    required ApiClient apiClient,
  }) : _tokenStorage = tokenStorage,
       _authApi = AuthApi(apiClient: apiClient);

  final TokenStorage _tokenStorage;
  final AuthApi _authApi;

  bool _initialized = false;
  String? _token;
  String? _role;
  AuthStatus _status = AuthStatus.loading;
  Future<void>? _initFuture;

  bool get isReady => _initialized;
  bool get isAuthenticated => _status == AuthStatus.authenticated;
  String get roleNormalized => normalizeRole(_role);
  String? get token => _token;
  AuthStatus get status => _status;

  Future<void> init() {
    if (_initialized) {
      return Future<void>.value();
    }
    if (_initFuture != null) {
      return _initFuture!;
    }
    _initFuture = _initInternal();
    return _initFuture!;
  }

  Future<void> _initInternal() async {
    _status = AuthStatus.loading;
    notifyListeners();
    try {
      final storedToken = await _tokenStorage.readToken();
      final storedRole = await _tokenStorage.readRole();
      if (storedToken != null && storedToken.trim().isNotEmpty) {
        _token = storedToken.trim();
        _role = normalizeRole(storedRole);
        _status = AuthStatus.authenticated;
      } else {
        _token = null;
        _role = null;
        _status = AuthStatus.anonymous;
      }
    } catch (_) {
      await _tokenStorage.clearAuth();
      _token = null;
      _role = null;
      _status = AuthStatus.anonymous;
    } finally {
      _initialized = true;
      notifyListeners();
    }
  }

  Future<AuthLoginResult> login(
    String email,
    String password, {
    bool requireAdmin = false,
  }) async {
    final result = await _authApi.login(email: email, password: password);
    if (requireAdmin && !result.isAdmin) {
      throw const AuthSessionException(
        code: 'not_authorized',
        message: 'Not authorized.',
      );
    }
    await _tokenStorage.saveAuth(token: result.token, role: result.role);
    _token = result.token;
    _role = normalizeRole(result.role);
    _status = AuthStatus.authenticated;
    if (!_initialized) {
      _initialized = true;
    }
    notifyListeners();
    return result;
  }

  Future<AuthLoginResult> register(String email, String password) async {
    await _authApi.register(email: email, password: password);
    return login(email, password);
  }

  Future<void> logout() async {
    await _tokenStorage.clearAuth();
    _token = null;
    _role = null;
    _status = AuthStatus.anonymous;
    if (!_initialized) {
      _initialized = true;
    }
    notifyListeners();
  }

  Future<void> invalidateToken() async {
    await logout();
  }
}

class AuthSessionException implements Exception {
  const AuthSessionException({required this.code, required this.message});

  final String code;
  final String message;

  @override
  String toString() {
    return '$code: $message';
  }
}
