import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hailo_core/config/api_config.dart';

void main() {
  group('ApiConfig.resolveEnvironmentFor', () {
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
      expect(staging, 'https://staging-tri-o-fliptrybe.onrender.com');
      expect(prod, 'https://tri-o-fliptrybe.onrender.com');
    });
  });
}
