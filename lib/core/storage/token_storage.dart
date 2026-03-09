import 'package:flutter_secure_storage/flutter_secure_storage.dart';

class TokenStorage {
  const TokenStorage({
    FlutterSecureStorage storage = const FlutterSecureStorage(),
  }) : _storage = storage;

  static const _tokenKey = 'auth_token';
  static const _roleKey = 'user_role';
  static const _refreshTokenKey = 'refresh_token';

  final FlutterSecureStorage _storage;

  Future<void> saveToken(String token) {
    return _storage.write(key: _tokenKey, value: token);
  }

  Future<void> saveAuth({
    required String token,
    required String role,
    String? refreshToken,
  }) async {
    final writes = <Future<void>>[saveToken(token), saveRole(role)];
    final normalizedRefreshToken = (refreshToken ?? '').trim();
    if (normalizedRefreshToken.isNotEmpty) {
      writes.add(saveRefreshToken(normalizedRefreshToken));
    } else {
      writes.add(deleteRefreshToken());
    }
    await Future.wait<void>(writes);
  }

  Future<String?> readToken() {
    return _storage.read(key: _tokenKey);
  }

  Future<void> deleteToken() {
    return _storage.delete(key: _tokenKey);
  }

  Future<void> saveRole(String role) {
    return _storage.write(key: _roleKey, value: role);
  }

  Future<String?> readRole() {
    return _storage.read(key: _roleKey);
  }

  Future<void> deleteRole() {
    return _storage.delete(key: _roleKey);
  }

  Future<void> saveRefreshToken(String refreshToken) {
    return _storage.write(key: _refreshTokenKey, value: refreshToken);
  }

  Future<String?> readRefreshToken() {
    return _storage.read(key: _refreshTokenKey);
  }

  Future<void> deleteRefreshToken() {
    return _storage.delete(key: _refreshTokenKey);
  }

  Future<void> clearAuth() async {
    await Future.wait<void>(<Future<void>>[
      deleteToken(),
      deleteRole(),
      deleteRefreshToken(),
    ]);
  }

  Future<void> writeValue(String key, String value) {
    return _storage.write(key: key, value: value);
  }

  Future<String?> readValue(String key) {
    return _storage.read(key: key);
  }

  Future<void> deleteValue(String key) {
    return _storage.delete(key: key);
  }
}
