import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:sentry_flutter/sentry_flutter.dart';

import 'app.dart';
import 'config/api_config.dart';
import 'config/env.dart';
import 'config/release_guard.dart';
import 'core/observability/app_observability.dart';

Future<void> main() async {
  unawaited(AppObservability.recordStartupStage(stage: 'app main entered'));
  WidgetsFlutterBinding.ensureInitialized();
  unawaited(AppObservability.recordStartupStage(stage: 'bindings initialized'));
  ReleaseGuard.enforceInRelease();
  await SentryFlutter.init(
    (options) {
      options.dsn = const String.fromEnvironment(
        'SENTRY_DSN',
        defaultValue: '',
      );
      options.environment = ApiConfig.environmentName;
      options.release = const String.fromEnvironment(
        'HAILO_RELEASE',
        defaultValue: 'local',
      );
      options.sendDefaultPii = false;
      options.beforeSend = AppObservability.beforeSend;
      options.tracesSampleRate = 0.2;
    },
    appRunner: () async {
      final packageInfo = await PackageInfo.fromPlatform();
      await AppObservability.setRuntimeContext(
        environment: AppEnv.name,
        appVersion: packageInfo.version,
        buildNumber: packageInfo.buildNumber,
        platform: defaultTargetPlatform.name,
      );
      unawaited(
        AppObservability.recordStartupStage(
          stage: 'env/config loaded',
          detail:
              'env=${AppEnv.name}, api=${ApiConfig.environmentName}, baseUrl=${ApiConfig.baseUrl}',
        ),
      );
      runApp(const MyApp());
    },
  );
}

class MyApp extends HailoCoreApp {
  const MyApp({super.key});
}
