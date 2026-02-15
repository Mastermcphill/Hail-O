import 'dart:io';

import 'package:dart_jsonwebtoken/dart_jsonwebtoken.dart';

class AuthTokenPayload {
  const AuthTokenPayload({
    required this.userId,
    required this.role,
    required this.issuedAt,
    required this.expiresAt,
  });

  final String userId;
  final String role;
  final DateTime issuedAt;
  final DateTime expiresAt;
}

class TokenService {
  TokenService({
    required String secret,
    Duration tokenTtl = const Duration(hours: 24),
  }) : _secret = secret,
       _tokenTtl = tokenTtl;

  factory TokenService.fromEnvironment() {
    final env = Platform.environment;
    final secret = env['JWT_SECRET']?.trim();
    return TokenService(
      secret: (secret == null || secret.isEmpty)
          ? 'dev-only-insecure-secret-change-me'
          : secret,
    );
  }

  final String _secret;
  final Duration _tokenTtl;
  static const Set<String> _allowedRoles = <String>{
    'rider',
    'driver',
    'admin',
    'fleet_owner',
    'system',
  };

  String issueToken({
    required String userId,
    required String role,
    DateTime? nowUtc,
  }) {
    final now = (nowUtc ?? DateTime.now()).toUtc();
    final jwt = JWT(<String, Object?>{
      'user_id': userId,
      'role': role,
      'issued_at': now.toIso8601String(),
    });
    return jwt.sign(SecretKey(_secret), expiresIn: _tokenTtl);
  }

  AuthTokenPayload verifyToken(String token) {
    final verified = JWT.verify(token, SecretKey(_secret));
    final payload = verified.payload;
    if (payload is! Map<String, dynamic>) {
      throw JWTException('invalid_payload');
    }

    final userId = (payload['user_id'] as String?)?.trim() ?? '';
    final role = (payload['role'] as String?)?.trim().toLowerCase() ?? '';
    if (userId.isEmpty || role.isEmpty) {
      throw JWTException('missing_auth_claims');
    }
    if (!_allowedRoles.contains(role)) {
      throw JWTException('invalid_role_claim');
    }

    final issuedAtRaw = payload['issued_at'] as String?;
    final issuedAt = issuedAtRaw == null
        ? DateTime.now().toUtc()
        : DateTime.parse(issuedAtRaw).toUtc();
    final expiresAtSeconds = payload['exp'];
    final expiresAt = expiresAtSeconds is int
        ? DateTime.fromMillisecondsSinceEpoch(
            expiresAtSeconds * 1000,
            isUtc: true,
          )
        : issuedAt.add(_tokenTtl);

    return AuthTokenPayload(
      userId: userId,
      role: role,
      issuedAt: issuedAt,
      expiresAt: expiresAt,
    );
  }
}
