import '../../../core/storage/token_storage.dart';

class StoredAuthTokens {
  const StoredAuthTokens({
    required this.accessToken,
    this.refreshToken,
    this.role,
  });

  final String accessToken;
  final String? refreshToken;
  final String? role;
}

abstract class AuthStorage {
  Future<void> saveTokens({
    required String accessToken,
    String? refreshToken,
    String? role,
  });

  Future<StoredAuthTokens?> loadTokens();

  Future<void> clearTokens();
}

class SecureAuthStorage implements AuthStorage {
  const SecureAuthStorage({required TokenStorage tokenStorage})
    : _tokenStorage = tokenStorage;

  final TokenStorage _tokenStorage;

  @override
  Future<void> saveTokens({
    required String accessToken,
    String? refreshToken,
    String? role,
  }) async {
    await _tokenStorage.saveAuth(
      token: accessToken.trim(),
      role: (role ?? '').trim().isEmpty ? 'rider' : role!.trim(),
      refreshToken: refreshToken?.trim(),
    );
  }

  @override
  Future<StoredAuthTokens?> loadTokens() async {
    final accessToken = (await _tokenStorage.readToken() ?? '').trim();
    final refreshToken = (await _tokenStorage.readRefreshToken() ?? '').trim();
    final role = (await _tokenStorage.readRole() ?? '').trim();
    if (accessToken.isEmpty && refreshToken.isEmpty) {
      return null;
    }
    return StoredAuthTokens(
      accessToken: accessToken,
      refreshToken: refreshToken.isEmpty ? null : refreshToken,
      role: role.isEmpty ? null : role,
    );
  }

  @override
  Future<void> clearTokens() {
    return _tokenStorage.clearAuth();
  }
}
