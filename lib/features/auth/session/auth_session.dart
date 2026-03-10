import 'dart:async';
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
    Duration startupStepTimeout = const Duration(seconds: 4),
    Duration startupNetworkTimeout = const Duration(seconds: 10),
  }) : _authStorage =
           authStorage ?? SecureAuthStorage(tokenStorage: tokenStorage),
       _authApi = AuthApi(apiClient: apiClient),
       _startupStepTimeout = startupStepTimeout,
       _startupNetworkTimeout = startupNetworkTimeout;

  final AuthStorage _authStorage;
  final AuthApi _authApi;
  final Duration _startupStepTimeout;
  final Duration _startupNetworkTimeout;

  bool _initialized = false;
  String? _token;
  String? _role;
  AuthStatus _status = AuthStatus.loading;
  Future<void>? _initFuture;
  String _startupStage = 'Preparing startup';
  String? _startupFailureCode;
  String? _startupFailureMessage;
  bool _startupNoticeDismissed = false;

  bool get isReady => _initialized;
  bool get isAuthenticated => _status == AuthStatus.authenticated;
  String get roleNormalized => normalizeRole(_role);
  String? get token => _token;
  AuthStatus get status => _status;
  String get startupStage => _startupStage;
  String? get startupFailureCode => _startupFailureCode;
  String? get startupFailureMessage => _startupFailureMessage;
  String? get startupNotice =>
      _startupNoticeDismissed ? null : _startupFailureMessage;

  void dismissStartupNotice() {
    if (_startupNoticeDismissed) {
      return;
    }
    _startupNoticeDismissed = true;
    notifyListeners();
  }

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
    _setStartupStage('auth/session restore started');
    try {
      final stored = await _criticalStartupStep<StoredAuthTokens?>(
        stage: 'reading secure session storage',
        future: _authStorage.loadTokens(),
        timeout: _startupStepTimeout,
        timeoutCode: 'startup_storage_timeout',
        timeoutMessage:
            'Session restore timed out while reading secure storage. The app will continue without a saved session.',
      );
      _setStartupStage('storage ready');
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
            await _clearTokensBestEffort();
            await _clearObservabilityBestEffort();
            _setAnonymousState();
          }
        } else {
          _setAuthenticatedState(
            token: normalizedToken,
            role: normalizeRole(storedRole),
          );
          await _attachUserToObservabilityBestEffort(
            token: normalizedToken,
            role: _role ?? 'rider',
          );
        }
      } else {
        _setAnonymousState();
        await _clearObservabilityBestEffort();
      }
      _clearStartupFailure();
      _setStartupStage('auth/session restore completed');
    } catch (error, stackTrace) {
      await _recoverFromStartupFailure(error, stackTrace);
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
      final refreshedAccessToken = await _criticalStartupStep<String>(
        stage: 'refreshing persisted session',
        future: _authApi.refreshAccessToken(
          refreshToken: normalizedRefreshToken,
        ),
        timeout: _startupNetworkTimeout,
        timeoutCode: 'startup_refresh_timeout',
        timeoutMessage:
            'Session refresh took too long. The app will continue without a saved session.',
      );
      final normalizedRole = normalizeRole(role);
      await _persistTokensBestEffort(
        accessToken: refreshedAccessToken,
        role: normalizedRole,
        refreshToken: normalizedRefreshToken,
      );
      _setAuthenticatedState(token: refreshedAccessToken, role: normalizedRole);
      await _attachUserToObservabilityBestEffort(
        token: refreshedAccessToken,
        role: normalizedRole,
      );
      return true;
    } on AuthStartupFailure {
      rethrow;
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

  Future<AuthLoginResult> register({
    required String email,
    required String password,
    String role = 'rider',
    String? displayName,
  }) async {
    await _authApi.register(
      email: email,
      password: password,
      role: role,
      displayName: displayName,
    );
    return login(email, password);
  }

  Future<void> logout() async {
    await _authStorage.clearTokens();
    await AppObservability.clearAuthenticatedUser();
    _setAnonymousState();
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
    _setAuthenticatedState(token: token, role: role);
    await _attachUserToObservability(token: token, role: _role ?? 'rider');
    if (!_initialized) {
      _initialized = true;
    }
    notifyListeners();
  }

  void _setAnonymousState() {
    _token = null;
    _role = null;
    _status = AuthStatus.anonymous;
  }

  void _setAuthenticatedState({required String token, required String role}) {
    _token = token;
    _role = normalizeRole(role);
    _status = AuthStatus.authenticated;
  }

  void _setStartupStage(String stage, {String? detail, bool notify = true}) {
    _startupStage = stage;
    unawaited(
      AppObservability.recordStartupStage(stage: stage, detail: detail),
    );
    if (notify) {
      notifyListeners();
    }
  }

  Future<T> _criticalStartupStep<T>({
    required String stage,
    required Future<T> future,
    required Duration timeout,
    required String timeoutCode,
    required String timeoutMessage,
  }) async {
    _setStartupStage(stage);
    try {
      return await future.timeout(timeout);
    } on TimeoutException catch (error) {
      throw AuthStartupFailure(
        code: timeoutCode,
        message: timeoutMessage,
        stage: stage,
        cause: error,
      );
    }
  }

  Future<void> _bestEffortStartupStep({
    required String stage,
    required Future<void> future,
    String? detail,
  }) async {
    try {
      await future.timeout(_startupStepTimeout);
    } on TimeoutException {
      unawaited(
        AppObservability.recordStartupStage(
          stage: '$stage skipped',
          detail:
              'Step exceeded ${_startupStepTimeout.inSeconds}s timeout${detail == null ? '' : ' ($detail)'}',
        ),
      );
    } catch (error) {
      unawaited(
        AppObservability.recordStartupStage(
          stage: '$stage skipped',
          detail: '$error${detail == null ? '' : ' ($detail)'}',
        ),
      );
    }
  }

  Future<void> _persistTokensBestEffort({
    required String accessToken,
    required String role,
    String? refreshToken,
  }) {
    return _bestEffortStartupStep(
      stage: 'persisting refreshed session',
      future: _authStorage.saveTokens(
        accessToken: accessToken,
        role: role,
        refreshToken: refreshToken,
      ),
    );
  }

  Future<void> _clearTokensBestEffort() {
    return _bestEffortStartupStep(
      stage: 'clearing unusable session',
      future: _authStorage.clearTokens(),
    );
  }

  Future<void> _attachUserToObservabilityBestEffort({
    required String token,
    required String role,
  }) {
    return _bestEffortStartupStep(
      stage: 'attaching session observability',
      future: _attachUserToObservability(token: token, role: role),
    );
  }

  Future<void> _clearObservabilityBestEffort() {
    return _bestEffortStartupStep(
      stage: 'clearing session observability',
      future: AppObservability.clearAuthenticatedUser(),
    );
  }

  void _clearStartupFailure() {
    _startupFailureCode = null;
    _startupFailureMessage = null;
    _startupNoticeDismissed = false;
  }

  Future<void> _recoverFromStartupFailure(
    Object error,
    StackTrace stackTrace,
  ) async {
    final failure = _describeStartupFailure(error);
    await _clearTokensBestEffort();
    await _clearObservabilityBestEffort();
    _setAnonymousState();
    _startupFailureCode = failure.code;
    _startupFailureMessage = failure.message;
    _startupNoticeDismissed = false;
    _setStartupStage(
      'auth/session restore completed',
      detail: '${failure.code} at ${failure.stage}',
      notify: false,
    );
    unawaited(
      AppObservability.recordStartupStage(
        stage: 'startup recovered in safe mode',
        detail: '${failure.code}: ${failure.message}\n$stackTrace',
      ),
    );
  }

  AuthStartupFailure _describeStartupFailure(Object error) {
    if (error is AuthStartupFailure) {
      return error;
    }
    return AuthStartupFailure(
      code: 'startup_restore_failed',
      message:
          'Session restore failed during startup. The app continued in safe mode.',
      stage: _startupStage,
      cause: error,
    );
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

class AuthStartupFailure implements Exception {
  const AuthStartupFailure({
    required this.code,
    required this.message,
    required this.stage,
    this.cause,
  });

  final String code;
  final String message;
  final String stage;
  final Object? cause;

  @override
  String toString() {
    return '$code at $stage: $message${cause == null ? '' : ' ($cause)'}';
  }
}
