import 'package:flutter/foundation.dart';

enum HailoEnvironment { dev, staging, prod }

class ApiConfig {
  static const String _developmentAndroidEmulatorUrl = 'http://10.0.2.2:8080';
  static const String _developmentIosSimulatorUrl = 'http://localhost:8080';
  static const String _developmentFallbackUrl = 'http://localhost:8080';
  static const String _stagingUrl =
      'https://staging-tri-o-fliptrybe.onrender.com';
  static const String _productionUrl = 'https://tri-o-fliptrybe.onrender.com';

  static const bool useProduction = bool.fromEnvironment(
    'HAILO_USE_PROD',
    defaultValue: false,
  );

  static const String _envDartDefine = String.fromEnvironment(
    'ENV',
    defaultValue: '',
  );
  static const String _explicitEnvironment = String.fromEnvironment(
    'HAILO_ENV',
    defaultValue: '',
  );
  static const String _flutterFlavor = String.fromEnvironment(
    'FLUTTER_APP_FLAVOR',
    defaultValue: '',
  );
  static const String _mockModeOverride = String.fromEnvironment(
    'HAILO_MOCK_MODE',
    defaultValue: '',
  );

  static HailoEnvironment get environment => _resolveEnvironment();
  static String get environmentName => environment.name;

  static bool get mockMode => resolveMockModeFor(
    environment: environment,
    mockModeOverride: _mockModeOverride,
  );

  static String get baseUrl {
    const baseOverride = String.fromEnvironment('BASE_URL', defaultValue: '');
    const override = String.fromEnvironment('HAILO_BASE_URL', defaultValue: '');
    if (baseOverride.trim().isNotEmpty) {
      return _normalize(baseOverride);
    }
    if (override.trim().isNotEmpty) {
      return _normalize(override);
    }

    return resolveBaseUrlFor(
      environment: environment,
      isWeb: kIsWeb,
      targetPlatform: defaultTargetPlatform,
    );
  }

  static HailoEnvironment _resolveEnvironment() {
    return resolveEnvironmentFor(
      envDefine: _envDartDefine,
      explicitEnvironment: _explicitEnvironment,
      flavor: _flutterFlavor,
      useProductionFallback: useProduction,
    );
  }

  static HailoEnvironment? _parseEnvironment(String value) {
    switch (value.trim().toLowerCase()) {
      case 'dev':
      case 'development':
        return HailoEnvironment.dev;
      case 'staging':
      case 'stage':
        return HailoEnvironment.staging;
      case 'prod':
      case 'production':
        return HailoEnvironment.prod;
      default:
        return null;
    }
  }

  @visibleForTesting
  static HailoEnvironment resolveEnvironmentFor({
    String envDefine = '',
    String explicitEnvironment = '',
    String flavor = '',
    bool useProductionFallback = false,
  }) {
    final fromEnv = _parseEnvironment(envDefine);
    if (fromEnv != null) {
      return fromEnv;
    }

    final fromExplicit = _parseEnvironment(explicitEnvironment);
    if (fromExplicit != null) {
      return fromExplicit;
    }

    final fromFlavor = _parseEnvironment(flavor);
    if (fromFlavor != null) {
      return fromFlavor;
    }

    if (useProductionFallback) {
      return HailoEnvironment.prod;
    }
    return HailoEnvironment.dev;
  }

  @visibleForTesting
  static String resolveBaseUrlFor({
    required HailoEnvironment environment,
    required bool isWeb,
    required TargetPlatform targetPlatform,
  }) {
    switch (environment) {
      case HailoEnvironment.prod:
        return _productionUrl;
      case HailoEnvironment.staging:
        return _stagingUrl;
      case HailoEnvironment.dev:
        if (isWeb) {
          return _developmentFallbackUrl;
        }
        switch (targetPlatform) {
          case TargetPlatform.android:
            return _developmentAndroidEmulatorUrl;
          case TargetPlatform.iOS:
            return _developmentIosSimulatorUrl;
          default:
            return _developmentFallbackUrl;
        }
    }
  }

  @visibleForTesting
  static bool resolveMockModeFor({
    required HailoEnvironment environment,
    String mockModeOverride = '',
  }) {
    if (environment == HailoEnvironment.prod) {
      return false;
    }
    final normalizedOverride = mockModeOverride.trim().toLowerCase();
    if (normalizedOverride == 'true') {
      return true;
    }
    if (normalizedOverride == 'false') {
      return false;
    }
    return false;
  }

  static String _normalize(String value) {
    final trimmed = value.trim();
    if (trimmed.endsWith('/')) {
      return trimmed.substring(0, trimmed.length - 1);
    }
    return trimmed;
  }
}
