import 'dart:convert';
import 'dart:math';

import 'package:crypto/crypto.dart';
import 'package:uuid/uuid.dart';

import '../../infra/token_service.dart';
import 'otp_provider.dart';
import 'phone_auth_store.dart';
import 'termii_otp_provider.dart';

class PhoneAuthFailure implements Exception {
  const PhoneAuthFailure({
    required this.statusCode,
    required this.code,
    required this.message,
  });

  final int statusCode;
  final String code;
  final String message;
}

class PhoneAuthService {
  PhoneAuthService({
    required PhoneAuthStore store,
    required TokenService tokenService,
    required bool devBypassEnabled,
    required String devBypassCode,
    required Duration otpTtl,
    required int otpCodeLength,
    required int otpMaxAttempts,
    required Duration otpLockoutDuration,
    required Duration refreshTokenTtl,
    OtpProvider? otpProvider,
    DateTime Function()? nowUtc,
    Uuid? uuid,
    Random? random,
    void Function(String line)? logSink,
  }) : _store = store,
       _tokenService = tokenService,
       _devBypassEnabled = devBypassEnabled,
       _devBypassCode = devBypassCode,
       _otpTtl = otpTtl,
       _otpCodeLength = otpCodeLength,
       _otpMaxAttempts = otpMaxAttempts,
       _otpLockoutDuration = otpLockoutDuration,
       _refreshTokenTtl = refreshTokenTtl,
       _otpProvider = otpProvider,
       _nowUtc = nowUtc ?? (() => DateTime.now().toUtc()),
       _uuid = uuid ?? const Uuid(),
       _random = random ?? Random.secure(),
       _logSink = logSink ?? print;

  factory PhoneAuthService.fromEnvironment({
    required PhoneAuthStore store,
    required TokenService tokenService,
    required String environment,
    required Map<String, String> envMap,
    DateTime Function()? nowUtc,
    Uuid? uuid,
    Random? random,
    void Function(String line)? logSink,
  }) {
    final normalizedEnvironment = environment.trim().toLowerCase();
    final isProduction = _isProductionEnvironment(normalizedEnvironment);
    final providerName = (envMap['OTP_PROVIDER'] ?? '').trim().toLowerCase();
    final explicitBypass = _parseBool(envMap['OTP_DEV_BYPASS']);
    final otpCodeLength = _readPositiveInt(
      envMap,
      'OTP_CODE_LENGTH',
      defaultValue: 6,
    ).clamp(4, 8);
    final otpTtl = Duration(
      seconds: _readPositiveInt(envMap, 'OTP_TTL_SECONDS', defaultValue: 300),
    );
    final otpMaxAttempts = _readPositiveInt(
      envMap,
      'OTP_MAX_ATTEMPTS',
      defaultValue: 5,
    );
    final otpLockoutDuration = Duration(
      seconds: _readPositiveInt(
        envMap,
        'OTP_LOCKOUT_SECONDS',
        defaultValue: 900,
      ),
    );
    final refreshTokenTtl = Duration(
      seconds: _readPositiveInt(
        envMap,
        'REFRESH_TOKEN_TTL_SECONDS',
        defaultValue: 2592000,
      ),
    );
    final devBypassCode = (envMap['OTP_DEV_BYPASS_CODE'] ?? '000000').trim();

    OtpProvider? otpProvider;
    switch (providerName) {
      case '':
      case 'none':
      case 'disabled':
        otpProvider = null;
        break;
      case 'termii':
        final apiKey = (envMap['TERMII_API_KEY'] ?? '').trim();
        final senderId = (envMap['TERMII_SENDER_ID'] ?? '').trim();
        if (apiKey.isEmpty || senderId.isEmpty) {
          throw StateError(
            'OTP_PROVIDER=termii requires TERMII_API_KEY and TERMII_SENDER_ID',
          );
        }
        otpProvider = TermiiOtpProvider(
          apiKey: apiKey,
          senderId: senderId,
          channel: (envMap['TERMII_CHANNEL'] ?? 'generic').trim(),
          apiBaseUrl:
              (envMap['TERMII_API_BASE_URL'] ?? 'https://api.ng.termii.com')
                  .trim(),
        );
        break;
      default:
        throw StateError('Unsupported OTP provider: $providerName');
    }

    final hasProvider = otpProvider != null;
    final devBypassEnabled = explicitBypass || (!isProduction && !hasProvider);
    if (isProduction && devBypassEnabled) {
      throw StateError('OTP dev bypass is not allowed in production');
    }
    if (!hasProvider && !devBypassEnabled) {
      throw StateError(
        'OTP provider is not configured. Set OTP_PROVIDER or OTP_DEV_BYPASS=true.',
      );
    }
    final codePattern = RegExp('^[0-9]{${otpCodeLength}}\$');
    if (!codePattern.hasMatch(devBypassCode) && devBypassEnabled) {
      throw StateError(
        'OTP_DEV_BYPASS_CODE must be exactly $otpCodeLength digits.',
      );
    }

    return PhoneAuthService(
      store: store,
      tokenService: tokenService,
      devBypassEnabled: devBypassEnabled,
      devBypassCode: devBypassCode,
      otpTtl: otpTtl,
      otpCodeLength: otpCodeLength,
      otpMaxAttempts: otpMaxAttempts,
      otpLockoutDuration: otpLockoutDuration,
      refreshTokenTtl: refreshTokenTtl,
      otpProvider: otpProvider,
      nowUtc: nowUtc,
      uuid: uuid,
      random: random,
      logSink: logSink,
    );
  }

  final PhoneAuthStore _store;
  final TokenService _tokenService;
  final bool _devBypassEnabled;
  final String _devBypassCode;
  final Duration _otpTtl;
  final int _otpCodeLength;
  final int _otpMaxAttempts;
  final Duration _otpLockoutDuration;
  final Duration _refreshTokenTtl;
  final OtpProvider? _otpProvider;
  final DateTime Function() _nowUtc;
  final Uuid _uuid;
  final Random _random;
  final void Function(String line) _logSink;

  static final RegExp _phonePattern = RegExp(r'^\+[1-9]\d{7,14}$');

  Future<Map<String, Object?>> requestOtp({required String phoneE164}) async {
    final phone = _normalizePhone(phoneE164);
    final now = _nowUtc();
    final code = _devBypassEnabled ? _devBypassCode : _generateOtpCode();

    await _store.createOtpChallenge(
      OtpChallengeRecord(
        id: _uuid.v4(),
        phoneE164: phone,
        codeHash: _hashOtp(phone, code),
        expiresAt: now.add(_otpTtl),
        attempts: 0,
        lockedUntil: null,
        createdAt: now,
      ),
    );

    if (_devBypassEnabled) {
      _logSink(
        jsonEncode(<String, Object?>{
          'event': 'otp_dev_bypass',
          'phone_e164': phone,
          'code': code,
        }),
      );
      return const <String, Object?>{'ok': true};
    }

    final provider = _otpProvider;
    if (provider == null) {
      throw const PhoneAuthFailure(
        statusCode: 503,
        code: 'otp_provider_unavailable',
        message: 'OTP provider is unavailable',
      );
    }
    try {
      await provider.sendOtp(phoneE164: phone, code: code, ttl: _otpTtl);
    } catch (_) {
      throw const PhoneAuthFailure(
        statusCode: 503,
        code: 'otp_delivery_failed',
        message: 'Unable to deliver OTP at the moment',
      );
    }
    return const <String, Object?>{'ok': true};
  }

  Future<Map<String, Object?>> verifyOtp({
    required String phoneE164,
    required String code,
  }) async {
    final phone = _normalizePhone(phoneE164);
    final normalizedCode = _normalizeCode(code);
    final now = _nowUtc();

    final challenge = await _store.findLatestOtpChallenge(phone);
    if (challenge == null) {
      throw const PhoneAuthFailure(
        statusCode: 401,
        code: 'invalid_otp_code',
        message: 'Invalid OTP code',
      );
    }
    final lockedUntil = challenge.lockedUntil;
    if (lockedUntil != null && lockedUntil.isAfter(now)) {
      throw const PhoneAuthFailure(
        statusCode: 423,
        code: 'otp_locked',
        message: 'OTP verification is temporarily locked',
      );
    }
    if (!challenge.expiresAt.isAfter(now)) {
      throw const PhoneAuthFailure(
        statusCode: 401,
        code: 'otp_expired',
        message: 'OTP code has expired',
      );
    }

    final expectedHash = _hashOtp(phone, normalizedCode);
    if (expectedHash != challenge.codeHash) {
      final nextAttempts = challenge.attempts + 1;
      final lockUntil = nextAttempts >= _otpMaxAttempts
          ? now.add(_otpLockoutDuration)
          : null;
      await _store.updateOtpChallengeState(
        challengeId: challenge.id,
        attempts: nextAttempts,
        lockedUntil: lockUntil,
      );
      if (lockUntil != null) {
        throw const PhoneAuthFailure(
          statusCode: 423,
          code: 'otp_locked',
          message: 'OTP verification is temporarily locked',
        );
      }
      throw const PhoneAuthFailure(
        statusCode: 401,
        code: 'invalid_otp_code',
        message: 'Invalid OTP code',
      );
    }

    await _store.consumeOtpChallenge(
      challengeId: challenge.id,
      consumedAt: now,
    );

    final user = await _resolveOrCreateUser(phone, now);
    final accessToken = _tokenService.issueToken(
      userId: user.id,
      role: user.role,
      nowUtc: now,
    );
    final refreshToken = _generateRefreshToken();
    await _store.createRefreshToken(
      RefreshTokenRecord(
        id: _uuid.v4(),
        userId: user.id,
        tokenHash: _hashToken(refreshToken),
        expiresAt: now.add(_refreshTokenTtl),
        revokedAt: null,
        createdAt: now,
      ),
    );

    return <String, Object?>{
      'access_token': accessToken,
      'refresh_token': refreshToken,
      'user': <String, Object?>{
        'id': user.id,
        'phone_e164': user.phoneE164,
        'created_at': user.createdAt.toUtc().toIso8601String(),
        'role': user.role,
      },
    };
  }

  Future<Map<String, Object?>> refreshAccessToken({
    required String refreshToken,
  }) async {
    final normalizedToken = refreshToken.trim();
    if (normalizedToken.isEmpty) {
      throw const PhoneAuthFailure(
        statusCode: 401,
        code: 'invalid_refresh_token',
        message: 'Refresh token is invalid',
      );
    }
    final now = _nowUtc();
    final record = await _store.findRefreshTokenByHash(
      _hashToken(normalizedToken),
    );
    if (record == null || record.revokedAt != null) {
      throw const PhoneAuthFailure(
        statusCode: 401,
        code: 'invalid_refresh_token',
        message: 'Refresh token is invalid',
      );
    }
    if (!record.expiresAt.isAfter(now)) {
      throw const PhoneAuthFailure(
        statusCode: 401,
        code: 'refresh_token_expired',
        message: 'Refresh token has expired',
      );
    }
    final user = await _store.findUserById(record.userId);
    if (user == null) {
      throw const PhoneAuthFailure(
        statusCode: 401,
        code: 'invalid_refresh_token',
        message: 'Refresh token is invalid',
      );
    }
    final accessToken = _tokenService.issueToken(
      userId: user.id,
      role: user.role,
      nowUtc: now,
    );
    return <String, Object?>{'access_token': accessToken};
  }

  Future<void> revokeRefreshToken({
    required String refreshToken,
    DateTime? revokedAt,
  }) async {
    final normalizedToken = refreshToken.trim();
    if (normalizedToken.isEmpty) {
      return;
    }
    final existing = await _store.findRefreshTokenByHash(
      _hashToken(normalizedToken),
    );
    if (existing == null || existing.revokedAt != null) {
      return;
    }
    await _store.revokeRefreshToken(
      tokenId: existing.id,
      revokedAt: revokedAt ?? _nowUtc(),
    );
  }

  Future<PhoneAuthUserRecord> _resolveOrCreateUser(
    String phoneE164,
    DateTime now,
  ) async {
    final existing = await _store.findUserByPhone(phoneE164);
    if (existing != null) {
      return existing;
    }
    return _store.createUser(
      userId: _uuid.v4(),
      phoneE164: phoneE164,
      createdAt: now,
    );
  }

  String _normalizePhone(String input) {
    final normalized = input.trim();
    if (!_phonePattern.hasMatch(normalized)) {
      throw const PhoneAuthFailure(
        statusCode: 400,
        code: 'invalid_phone_e164',
        message: 'phone_e164 must be a valid E.164 number',
      );
    }
    return normalized;
  }

  String _normalizeCode(String input) {
    final normalized = input.trim();
    final codePattern = RegExp('^[0-9]{${_otpCodeLength}}\$');
    if (!codePattern.hasMatch(normalized)) {
      throw const PhoneAuthFailure(
        statusCode: 401,
        code: 'invalid_otp_code',
        message: 'Invalid OTP code',
      );
    }
    return normalized;
  }

  String _generateOtpCode() {
    final buffer = StringBuffer();
    for (var index = 0; index < _otpCodeLength; index++) {
      buffer.write(_random.nextInt(10));
    }
    return buffer.toString();
  }

  String _generateRefreshToken() {
    final bytes = List<int>.generate(48, (_) => _random.nextInt(256));
    return base64UrlEncode(bytes);
  }

  String _hashOtp(String phoneE164, String code) {
    final payload = '$phoneE164|$code';
    return sha256.convert(utf8.encode(payload)).toString();
  }

  String _hashToken(String token) {
    return sha256.convert(utf8.encode(token)).toString();
  }

  static bool _isProductionEnvironment(String environment) {
    return environment == 'production' || environment == 'prod';
  }

  static int _readPositiveInt(
    Map<String, String> envMap,
    String key, {
    required int defaultValue,
  }) {
    final parsed = int.tryParse((envMap[key] ?? '').trim());
    if (parsed == null || parsed <= 0) {
      return defaultValue;
    }
    return parsed;
  }

  static bool _parseBool(String? value) {
    final normalized = value?.trim().toLowerCase() ?? '';
    return normalized == '1' ||
        normalized == 'true' ||
        normalized == 'yes' ||
        normalized == 'y' ||
        normalized == 'on';
  }
}
