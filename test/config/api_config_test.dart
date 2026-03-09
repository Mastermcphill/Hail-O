import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hailo_core/config/api_config.dart';

void main() {
  group('ApiConfig.resolveEnvironmentFor', () {
    test('prefers ENV dart-define over legacy variables', () {
      final env = ApiConfig.resolveEnvironmentFor(
        envDefine: 'production',
        explicitEnvironment: 'staging',
        flavor: 'dev',
      );
      expect(env, HailoEnvironment.prod);
    });

    test('prefers explicit HAILO_ENV', () {
      final env = ApiConfig.resolveEnvironmentFor(
        explicitEnvironment: 'staging',
        flavor: 'prod',
      );
      expect(env, HailoEnvironment.staging);
    });

    test('falls back to flavor when explicit env missing', () {
      final env = ApiConfig.resolveEnvironmentFor(flavor: 'prod');
      expect(env, HailoEnvironment.prod);
    });

    test('falls back to legacy prod flag when no env/flavor', () {
      final env = ApiConfig.resolveEnvironmentFor(useProductionFallback: true);
      expect(env, HailoEnvironment.prod);
    });

    test('defaults to dev when nothing is provided', () {
      final env = ApiConfig.resolveEnvironmentFor();
      expect(env, HailoEnvironment.dev);
    });
  });

  group('ApiConfig.resolveBaseUrlFor', () {
    test('uses emulator host for android dev', () {
      final url = ApiConfig.resolveBaseUrlFor(
        environment: HailoEnvironment.dev,
        isWeb: false,
        targetPlatform: TargetPlatform.android,
      );
      expect(url, 'http://10.0.2.2:8080');
    });

    test('uses localhost for iOS dev', () {
      final url = ApiConfig.resolveBaseUrlFor(
        environment: HailoEnvironment.dev,
        isWeb: false,
        targetPlatform: TargetPlatform.iOS,
      );
      expect(url, 'http://localhost:8080');
    });

    test('uses staging and prod urls', () {
      final staging = ApiConfig.resolveBaseUrlFor(
        environment: HailoEnvironment.staging,
        isWeb: false,
        targetPlatform: TargetPlatform.android,
      );
      final prod = ApiConfig.resolveBaseUrlFor(
        environment: HailoEnvironment.prod,
        isWeb: false,
        targetPlatform: TargetPlatform.android,
      );
      expect(staging, 'https://hail-o-api-staging.onrender.com');
      expect(prod, 'https://hail-o-api.onrender.com');
    });
  });

  group('ApiConfig.resolveMockModeFor', () {
    test('prod defaults to mock disabled', () {
      final mockMode = ApiConfig.resolveMockModeFor(
        environment: HailoEnvironment.prod,
      );
      expect(mockMode, isFalse);
    });

    test('staging defaults to mock disabled', () {
      final mockMode = ApiConfig.resolveMockModeFor(
        environment: HailoEnvironment.staging,
      );
      expect(mockMode, isFalse);
    });

    test('dev defaults to mock disabled', () {
      final mockMode = ApiConfig.resolveMockModeFor(
        environment: HailoEnvironment.dev,
      );
      expect(mockMode, isFalse);
    });

    test('explicit override enables mock mode outside prod', () {
      final mockMode = ApiConfig.resolveMockModeFor(
        environment: HailoEnvironment.dev,
        mockModeOverride: 'true',
      );
      expect(mockMode, isTrue);
    });
  });
}
