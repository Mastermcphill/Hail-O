import 'package:flutter/foundation.dart';

class ApiConfig {
  static const String _developmentAndroidEmulatorUrl = 'http://10.0.2.2:8080';
  static const String _developmentIosSimulatorUrl = 'http://localhost:8080';
  static const String _developmentFallbackUrl = 'http://localhost:8080';
  static const String _productionUrl = 'https://tri-o-fliptrybe.onrender.com';

  static const bool useProduction = bool.fromEnvironment(
    'HAILO_USE_PROD',
    defaultValue: false,
  );

  static const bool mockMode = bool.fromEnvironment(
    'HAILO_MOCK_MODE',
    defaultValue: true,
  );

  static String get baseUrl {
    const override = String.fromEnvironment('HAILO_BASE_URL', defaultValue: '');
    if (override.trim().isNotEmpty) {
      return _normalize(override);
    }

    if (useProduction) {
      return _productionUrl;
    }

    if (kIsWeb) {
      return _developmentFallbackUrl;
    }

    switch (defaultTargetPlatform) {
      case TargetPlatform.android:
        return _developmentAndroidEmulatorUrl;
      case TargetPlatform.iOS:
        return _developmentIosSimulatorUrl;
      default:
        return _developmentFallbackUrl;
    }
  }

  static String _normalize(String value) {
    final trimmed = value.trim();
    if (trimmed.endsWith('/')) {
      return trimmed.substring(0, trimmed.length - 1);
    }
    return trimmed;
  }
}
