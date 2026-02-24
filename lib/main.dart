import 'package:flutter/material.dart';
import 'package:sentry_flutter/sentry_flutter.dart';

import 'app.dart';
import 'config/api_config.dart';
import 'core/observability/app_observability.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await SentryFlutter.init((options) {
    options.dsn = const String.fromEnvironment('SENTRY_DSN', defaultValue: '');
    options.environment = ApiConfig.environmentName;
    options.release = const String.fromEnvironment(
      'HAILO_RELEASE',
      defaultValue: 'local',
    );
    options.sendDefaultPii = false;
    options.beforeSend = AppObservability.beforeSend;
    options.tracesSampleRate = 0.2;
  }, appRunner: () => runApp(const MyApp()));
}

class MyApp extends HailoCoreApp {
  const MyApp({super.key});
}
