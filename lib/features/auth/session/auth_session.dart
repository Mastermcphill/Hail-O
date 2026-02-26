import 'dart:convert';

import 'package:flutter/foundation.dart';

import '../../../core/api/api_client.dart';
import '../../../core/observability/app_observability.dart';
import '../../../core/routing/role_routes.dart';
import '../../../core/storage/token_storage.dart';
import '../data/auth_api.dart';
import 'auth_storage.dart';

enum AuthStatus { loading, anonymous, authenticated }

class AuthSession extends ChangeNotifier {
  AuthSession({
    required TokenStorage tokenStorage,
    required ApiClient apiClient,
    AuthStorage? authStorage,
  }) : _authStorage =
           authStorage ?? SecureAuthStorage(tokenStorage: tokenStorage),
       _authApi = AuthApi(apiClient: apiClient);

  final AuthStorage _authStorage;
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
      final stored = await _authStorage.loadTokens();
      final storedToken = stored?.accessToken ?? '';
      final storedRole = stored?.role;
      final storedRefreshToken = stored?.refreshToken;
      if (storedToken.isNotEmpty) {
        final normalizedToken = storedToken;
        if (_isTokenInvalidOrExpired(normalizedToken)) {
          final refreshed = await _refreshUsingStoredToken(
            refreshToken: storedRefreshToken,
            role: storedRole,
          );
          if (!refreshed) {
            await _authStorage.clearTokens();
            await AppObservability.clearAuthenticatedUser();
            _token = null;
            _role = null;
            _status = AuthStatus.anonymous;
          }
        } else {
          _token = normalizedToken;
          _role = normalizeRole(storedRole);
          _status = AuthStatus.authenticated;
          await _attachUserToObservability(
            token: normalizedToken,
            role: _role ?? 'rider',
          );
        }
      } else {
        _token = null;
        _role = null;
        _status = AuthStatus.anonymous;
        await AppObservability.clearAuthenticatedUser();
      }
    } catch (_) {
      await _authStorage.clearTokens();
      await AppObservability.clearAuthenticatedUser();
      _token = null;
      _role = null;
      _status = AuthStatus.anonymous;
    } finally {
      _initialized = true;
      notifyListeners();
    }
  }

  Future<bool> _refreshUsingStoredToken({
    required String? refreshToken,
    required String? role,
  }) async {
    final normalizedRefreshToken = (refreshToken ?? '').trim();
    if (normalizedRefreshToken.isEmpty) {
      return false;
    }
    try {
      final refreshedAccessToken = await _authApi.refreshAccessToken(
        refreshToken: normalizedRefreshToken,
      );
      final normalizedRole = normalizeRole(role);
      await _authStorage.saveTokens(
        accessToken: refreshedAccessToken,
        role: normalizedRole,
        refreshToken: normalizedRefreshToken,
      );
      _token = refreshedAccessToken;
      _role = normalizedRole;
      _status = AuthStatus.authenticated;
      await _attachUserToObservability(
        token: refreshedAccessToken,
        role: normalizedRole,
      );
      return true;
    } catch (_) {
      return false;
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
    await _persistSession(token: result.token, role: result.role);
    return result;
  }

  Future<void> requestOtp(String phoneE164) {
    return _authApi.requestOtp(phoneE164: phoneE164);
  }

  Future<AuthLoginResult> verifyOtp({
    required String phoneE164,
    required String code,
  }) async {
    final result = await _authApi.verifyOtp(phoneE164: phoneE164, code: code);
    await _persistSession(
      token: result.accessToken,
      role: result.role,
      refreshToken: result.refreshToken,
    );
    return AuthLoginResult(token: result.accessToken, role: result.role);
  }

  Future<AuthLoginResult> register(String email, String password) async {
    await _authApi.register(email: email, password: password);
    return login(email, password);
  }

  Future<void> logout() async {
    await _authStorage.clearTokens();
    await AppObservability.clearAuthenticatedUser();
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

  Future<void> _persistSession({
    required String token,
    required String role,
    String? refreshToken,
  }) async {
    await _authStorage.saveTokens(
      accessToken: token,
      role: role,
      refreshToken: refreshToken,
    );
    _token = token;
    _role = normalizeRole(role);
    _status = AuthStatus.authenticated;
    await _attachUserToObservability(token: token, role: _role ?? 'rider');
    if (!_initialized) {
      _initialized = true;
    }
    notifyListeners();
  }

  Future<void> _attachUserToObservability({
    required String token,
    required String role,
  }) {
    final parts = token.split('.');
    if (parts.length != 3) {
      return AppObservability.setAuthenticatedUser(role: role);
    }
    final payloadMap = _decodeJwtPayload(parts[1]);
    final userId = _firstNonEmptyString(<Object?>[
      payloadMap?['user_id'],
      payloadMap?['sub'],
      payloadMap?['uid'],
      payloadMap?['id'],
    ]);
    return AppObservability.setAuthenticatedUser(userId: userId, role: role);
  }

  bool _isTokenInvalidOrExpired(String token) {
    final parts = token.split('.');
    if (parts.length != 3) {
      return true;
    }

    final payloadMap = _decodeJwtPayload(parts[1]);
    if (payloadMap == null) {
      return true;
    }

    final expirationSeconds = _readExpirationSeconds(payloadMap['exp']);
    if (expirationSeconds == null) {
      // Backward compatibility for tokens without exp claim.
      return false;
    }

    final expiration = DateTime.fromMillisecondsSinceEpoch(
      expirationSeconds * 1000,
      isUtc: true,
    );
    final now = DateTime.now().toUtc();
    return !expiration.isAfter(now);
  }

  Map<String, dynamic>? _decodeJwtPayload(String segment) {
    try {
      final normalized = base64Url.normalize(segment);
      final decoded = utf8.decode(base64Url.decode(normalized));
      final dynamic parsed = jsonDecode(decoded);
      if (parsed is Map<String, dynamic>) {
        return parsed;
      }
      if (parsed is Map) {
        return parsed.map(
          (key, value) => MapEntry<String, dynamic>(key.toString(), value),
        );
      }
      return null;
    } catch (_) {
      return null;
    }
  }

  int? _readExpirationSeconds(Object? value) {
    if (value is int) {
      return value;
    }
    if (value is num) {
      return value.toInt();
    }
    if (value is String) {
      return int.tryParse(value.trim());
    }
    return null;
  }

  String? _firstNonEmptyString(List<Object?> values) {
    for (final value in values) {
      if (value is String && value.trim().isNotEmpty) {
        return value.trim();
      }
      if (value is num) {
        return value.toString();
      }
    }
    return null;
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
